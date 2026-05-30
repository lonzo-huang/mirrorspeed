#include "amneziawg_flutter_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>
#include <flutter/event_stream_handler_functions.h>

#include <windows.h>
#include <winsvc.h>
#include <shlobj.h>
#include <strsafe.h>

#include <algorithm>
#include <chrono>
#include <codecvt>
#include <fstream>
#include <locale>
#include <map>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#pragma comment(lib, "advapi32.lib")

namespace amneziawg_flutter {

// -- String helpers ---------------------------------------------------------

static std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return {};
  int sz = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
  std::wstring out(sz, 0);
  MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), out.data(), sz);
  return out;
}

static std::string WideToUtf8(const std::wstring& w) {
  if (w.empty()) return {};
  int sz = WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(),
                                nullptr, 0, nullptr, nullptr);
  std::string out(sz, 0);
  WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(),
                       out.data(), sz, nullptr, nullptr);
  return out;
}

static std::string LastErrorString() {
  DWORD err = GetLastError();
  LPWSTR buf = nullptr;
  FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
                     FORMAT_MESSAGE_IGNORE_INSERTS,
                 nullptr, err, 0, (LPWSTR)&buf, 0, nullptr);
  std::string msg = buf ? WideToUtf8(buf) : "unknown error";
  LocalFree(buf);
  // Trim trailing newline
  while (!msg.empty() && (msg.back() == '\r' || msg.back() == '\n'))
    msg.pop_back();
  return msg;
}

// -- Registration ----------------------------------------------------------

// static
void AmneziawgFlutterPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {

  auto method_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(),
          "com.amneziawg.flutter/awgcontrol",
          &flutter::StandardMethodCodec::GetInstance());

  auto event_channel =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(),
          "com.amneziawg.flutter/awgstage",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<AmneziawgFlutterPlugin>(
      registrar, std::move(method_channel), std::move(event_channel));

  registrar->AddPlugin(std::move(plugin));
}

AmneziawgFlutterPlugin::AmneziawgFlutterPlugin(
    flutter::PluginRegistrarWindows* registrar,
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel,
    std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel)
    : registrar_(registrar),
      method_channel_(std::move(method_channel)),
      event_channel_(std::move(event_channel)) {

  method_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  auto handler = std::make_unique<
      flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      [this](const flutter::EncodableValue* args,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
                 sink) -> std::unique_ptr<flutter::StreamHandlerError<>> {
        event_sink_ = std::move(sink);
        StartMonitoring();
        return nullptr;
      },
      [this](const flutter::EncodableValue* args)
          -> std::unique_ptr<flutter::StreamHandlerError<>> {
        StopMonitoring();
        event_sink_ = nullptr;
        return nullptr;
      });
  event_channel_->SetStreamHandler(std::move(handler));
}

AmneziawgFlutterPlugin::~AmneziawgFlutterPlugin() {
  StopMonitoring();
}

// -- Method dispatch --------------------------------------------------------

void AmneziawgFlutterPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

  const auto& method = call.method_name();
  const auto* args   = std::get_if<flutter::EncodableMap>(call.arguments());

  auto get_str = [&](const std::string& key) -> std::string {
    if (!args) return {};
    auto it = args->find(flutter::EncodableValue(key));
    if (it == args->end()) return {};
    const auto* v = std::get_if<std::string>(&it->second);
    return v ? *v : "";
  };

  if (method == "initialize") {
    std::string name = get_str("win32ServiceName");
    if (name.empty()) name = get_str("localizedDescription");
    if (name.empty()) name = "awg0";
    Initialize(name, std::move(result));

  } else if (method == "start") {
    std::string conf        = get_str("wgQuickConfig");
    std::string server_addr = get_str("serverAddress");
    // The tunnel name was set during initialize; fall back to "awg0"
    std::string svc_name = service_name_.empty()
                               ? "awg0"
                               : WideToUtf8(service_name_);
    if (conf.empty()) {
      result->Error("MISSING_ARGS", "wgQuickConfig is required", nullptr);
      return;
    }
    StartTunnel(conf, svc_name, std::move(result));

  } else if (method == "stop") {
    StopTunnel(std::move(result));

  } else if (method == "stage") {
    GetStage(std::move(result));

  } else if (method == "checkPermission") {
    // No special permission needed on Windows
    result->Success(flutter::EncodableValue());

  } else {
    result->NotImplemented();
  }
}

// -- Tunnel operations ------------------------------------------------------

void AmneziawgFlutterPlugin::Initialize(
    const std::string& tunnel_name,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

  service_name_ = Utf8ToWide(tunnel_name);
  result->Success(flutter::EncodableValue());
}

void AmneziawgFlutterPlugin::StartTunnel(
    const std::string& wg_conf,
    const std::string& tunnel_name,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

  service_name_ = Utf8ToWide(tunnel_name);

  // 1. Write config file
  std::wstring dir  = GetConfDir();
  CreateDirectoryW(dir.c_str(), nullptr);
  conf_path_ = dir + L"\\" + service_name_ + L".conf";

  if (!WriteConfFile(conf_path_, wg_conf)) {
    result->Error("WRITE_CONF_FAILED",
                  "Failed to write AWG config: " + LastErrorString(),
                  nullptr);
    return;
  }

  // 2. Stop any existing service with the same name
  StopAndRemoveService(service_name_);
  Sleep(500);

  // 3. Start new service
  if (!InstallAndStartService(conf_path_, service_name_)) {
    result->Error("START_FAILED",
                  "Failed to start AWG tunnel service: " + LastErrorString(),
                  nullptr);
    return;
  }

  result->Success(flutter::EncodableValue());
  SendStageEvent("connecting");
  StartMonitoring();
}

void AmneziawgFlutterPlugin::StopTunnel(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

  StopMonitoring();
  if (!service_name_.empty()) {
    StopAndRemoveService(service_name_);
  }
  // Remove the conf file
  if (!conf_path_.empty()) {
    DeleteFileW(conf_path_.c_str());
    conf_path_.clear();
  }
  result->Success(flutter::EncodableValue());
  SendStageEvent("disconnected");
}

void AmneziawgFlutterPlugin::GetStage(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  std::string stage = service_name_.empty()
                          ? "no_connection"
                          : QueryServiceStage(service_name_);
  result->Success(flutter::EncodableValue(stage));
}

// -- Helpers ----------------------------------------------------------------

std::wstring AmneziawgFlutterPlugin::GetConfDir() const {
  wchar_t tmp[MAX_PATH];
  GetTempPathW(MAX_PATH, tmp);
  return std::wstring(tmp) + L"awg";
}

// Find amneziawg_svc.exe next to the running executable or in its bin/ folder.
std::wstring AmneziawgFlutterPlugin::GetSvcExePath() const {
  wchar_t exePath[MAX_PATH];
  GetModuleFileNameW(nullptr, exePath, MAX_PATH);

  // Strip filename → directory
  std::wstring dir(exePath);
  auto slash = dir.rfind(L'\\');
  if (slash != std::wstring::npos) dir = dir.substr(0, slash);

  // Candidates: <exedir>\amneziawg_svc.exe, <exedir>\bin\amneziawg_svc.exe
  std::vector<std::wstring> candidates = {
      dir + L"\\amneziawg_svc.exe",
      dir + L"\\bin\\amneziawg_svc.exe",
      dir + L"\\amneziawg\\amneziawg_svc.exe",
  };
  for (const auto& c : candidates) {
    if (GetFileAttributesW(c.c_str()) != INVALID_FILE_ATTRIBUTES) return c;
  }
  return {};
}

bool AmneziawgFlutterPlugin::WriteConfFile(const std::wstring& path,
                                            const std::string& contents) {
  HANDLE hFile = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (hFile == INVALID_HANDLE_VALUE) return false;
  DWORD written;
  bool ok = WriteFile(hFile, contents.data(), (DWORD)contents.size(),
                       &written, nullptr) && written == (DWORD)contents.size();
  CloseHandle(hFile);
  return ok;
}

// Install and start a Windows service that runs the AWG tunnel.
// amneziawg_svc.exe <conf_path> is the expected interface.
bool AmneziawgFlutterPlugin::InstallAndStartService(
    const std::wstring& conf_path,
    const std::wstring& service_name) {

  std::wstring svc_exe = GetSvcExePath();
  if (svc_exe.empty()) {
    SetLastError(ERROR_FILE_NOT_FOUND);
    return false;
  }

  // Build binary path with quoted conf file argument
  std::wstring bin_path = L"\"" + svc_exe + L"\" \"" + conf_path + L"\"";

  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_ALL_ACCESS);
  if (!scm) return false;

  // Try to open existing service first
  SC_HANDLE svc = OpenServiceW(scm, service_name.c_str(), SERVICE_ALL_ACCESS);
  if (!svc) {
    // Create new service
    svc = CreateServiceW(
        scm,
        service_name.c_str(),
        (L"AmneziaWG Tunnel: " + service_name).c_str(),
        SERVICE_ALL_ACCESS,
        SERVICE_WIN32_OWN_PROCESS,
        SERVICE_DEMAND_START,
        SERVICE_ERROR_NORMAL,
        bin_path.c_str(),
        nullptr, nullptr, nullptr, nullptr, nullptr);
  }
  if (!svc) {
    CloseServiceHandle(scm);
    return false;
  }

  bool started = StartServiceW(svc, 0, nullptr) != FALSE;
  if (!started && GetLastError() == ERROR_SERVICE_ALREADY_RUNNING) {
    started = true;
  }

  CloseServiceHandle(svc);
  CloseServiceHandle(scm);
  return started;
}

bool AmneziawgFlutterPlugin::StopAndRemoveService(
    const std::wstring& service_name) {

  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_ALL_ACCESS);
  if (!scm) return false;

  SC_HANDLE svc = OpenServiceW(scm, service_name.c_str(), SERVICE_ALL_ACCESS);
  if (!svc) {
    CloseServiceHandle(scm);
    return false;
  }

  SERVICE_STATUS status{};
  ControlService(svc, SERVICE_CONTROL_STOP, &status);

  // Wait up to 5 seconds for service to stop
  for (int i = 0; i < 50; ++i) {
    if (!QueryServiceStatus(svc, &status)) break;
    if (status.dwCurrentState == SERVICE_STOPPED) break;
    Sleep(100);
  }

  bool deleted = DeleteService(svc) != FALSE;
  CloseServiceHandle(svc);
  CloseServiceHandle(scm);
  return deleted;
}

// Map Windows service state → our stage string
std::string AmneziawgFlutterPlugin::QueryServiceStage(
    const std::wstring& service_name) const {

  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  if (!scm) return "no_connection";

  SC_HANDLE svc = OpenServiceW(scm, service_name.c_str(), SERVICE_QUERY_STATUS);
  if (!svc) {
    CloseServiceHandle(scm);
    return "no_connection";
  }

  SERVICE_STATUS status{};
  bool ok = QueryServiceStatus(svc, &status) != FALSE;
  CloseServiceHandle(svc);
  CloseServiceHandle(scm);

  if (!ok) return "no_connection";

  switch (status.dwCurrentState) {
    case SERVICE_RUNNING:         return "connected";
    case SERVICE_START_PENDING:   return "connecting";
    case SERVICE_STOP_PENDING:    return "disconnecting";
    case SERVICE_STOPPED:         return "disconnected";
    default:                      return "no_connection";
  }
}

// -- Event / monitoring -----------------------------------------------------

void AmneziawgFlutterPlugin::StartMonitoring() {
  if (monitor_running_.exchange(true)) return; // already running
  monitor_thread_ = std::thread([this] { MonitorLoop(); });
  monitor_thread_.detach();
}

void AmneziawgFlutterPlugin::StopMonitoring() {
  monitor_running_.store(false);
}

void AmneziawgFlutterPlugin::MonitorLoop() {
  std::string last_stage;
  while (monitor_running_.load()) {
    std::string stage = service_name_.empty()
                            ? "no_connection"
                            : QueryServiceStage(service_name_);
    if (stage != last_stage) {
      last_stage = stage;
      SendStageEvent(stage);
    }
    // Stop polling once the service has fully stopped
    if (stage == "disconnected" || stage == "no_connection") {
      if (last_stage != "connecting") break; // avoid exiting prematurely
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
  }
  monitor_running_.store(false);
}

void AmneziawgFlutterPlugin::SendStageEvent(const std::string& stage) {
  if (!event_sink_) return;
  event_sink_->Success(flutter::EncodableValue(stage));
}

}  // namespace amneziawg_flutter
