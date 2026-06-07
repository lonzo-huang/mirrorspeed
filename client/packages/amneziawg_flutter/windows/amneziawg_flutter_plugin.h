#ifndef FLUTTER_PLUGIN_AMNEZIAWG_FLUTTER_PLUGIN_H_
#define FLUTTER_PLUGIN_AMNEZIAWG_FLUTTER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <memory>
#include <string>
#include <thread>
#include <atomic>

namespace amneziawg_flutter {

// -- AWG Windows tunnel manager ------------------------------------------------
//
// On Windows, AmneziaWG (and WireGuard) tunnels are managed as Windows
// services. This plugin:
//   1. Writes the AWG config to a temp file under %TEMP%\awg\<name>.conf
//   2. Installs a Windows service via the AWG tunnel service executable
//      (amneziawg_svc.exe) which must be bundled next to the app .exe.
//      Alternatively it calls tunnel.dll via its exported RunTunnel() API.
//   3. Monitors the service state and forwards status events to Flutter.
//
// Required files (place alongside your app .exe or in a 'bin/' subfolder):
//   - amneziawg_svc.exe  (from https://github.com/amnezia-vpn/amneziawg-windows)
//   - tunnel.dll
//   - wireguard.dll
//   - wintun.dll
//
// If the binaries are absent the plugin gracefully returns an error so the
// Dart layer can fall back to the wstunnel relay path.

class AmneziawgFlutterPlugin final : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  AmneziawgFlutterPlugin(
      flutter::PluginRegistrarWindows*                    registrar,
      std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel,
      std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel);

  virtual ~AmneziawgFlutterPlugin();

  // Non-copyable.
  AmneziawgFlutterPlugin(const AmneziawgFlutterPlugin&) = delete;
  AmneziawgFlutterPlugin& operator=(const AmneziawgFlutterPlugin&) = delete;

 private:
  // -- State ------------------------------------------------------------------
  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;

  std::wstring service_name_;          // Windows service name (= tunnel name)
  std::wstring tunnel_description_;     // WinTun adapter description (localized)
  std::wstring conf_path_;             // Path to the written .conf file
  std::atomic<bool> monitor_running_{false};
  std::thread monitor_thread_;

  // -- Method / Event handlers ------------------------------------------------
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // -- Tunnel operations ------------------------------------------------------
  void Initialize(const std::string& tunnel_name,
                  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void StartTunnel(const std::string& wg_conf,
                   const std::string& tunnel_name,
                   std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void StopTunnel(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void GetStage(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // -- Helpers ----------------------------------------------------------------
  std::wstring GetConfDir() const;
  std::wstring GetSvcExePath() const;
  bool WriteConfFile(const std::wstring& path, const std::string& contents);
  bool InstallAndStartService(const std::wstring& conf_path,
                               const std::wstring& service_name);
  bool StopAndRemoveService(const std::wstring& service_name);
  // Stop+remove any tunnel service this app may have left running (current
  // session and well-known default names). Removing the service tears down the
  // WinTun adapter and, with it, every route the tunnel installed — so traffic
  // is never blackholed by a leaked route table after the app exits or crashed.
  void CleanupStaleTunnels();
  std::string QueryServiceStage(const std::wstring& service_name) const;

  void StartMonitoring();
  void StopMonitoring();
  void MonitorLoop();

  void SendStageEvent(const std::string& stage);
};

}  // namespace amneziawg_flutter

#endif  // FLUTTER_PLUGIN_AMNEZIAWG_FLUTTER_PLUGIN_H_
