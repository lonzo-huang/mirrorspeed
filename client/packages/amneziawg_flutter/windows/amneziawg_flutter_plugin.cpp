// winsock2.h MUST come before any windows.h (pulled in by flutter headers below),
// otherwise windows.h includes the legacy winsock.h and iphlpapi/netioapi's
// ws2def.h conflicts ("Do not include winsock.h and ws2def.h in the same module").
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>   // GetIfTable2 — tunnel adapter byte counters

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
#pragma comment(lib, "iphlpapi.lib")

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

  // Crash recovery: if a previous run was killed (crash / Task Manager / power
  // loss) the tunnel service may still be running with its routes installed,
  // blackholing all traffic. Remove any leftover tunnel on startup.
  CleanupStaleTunnels();
}

AmneziawgFlutterPlugin::~AmneziawgFlutterPlugin() {
  StopMonitoring();
  // Always tear the tunnel down on app exit so a normal close never leaves the
  // WinTun adapter and its route table behind (which would break the user's
  // internet until a manual reboot/route flush).
  if (!service_name_.empty()) StopAndRemoveService(service_name_);
  CleanupStaleTunnels();
  if (!conf_path_.empty()) { DeleteFileW(conf_path_.c_str()); conf_path_.clear(); }
}

// Stop+remove the current and well-known tunnel services. Safe to call when
// nothing is running (OpenService simply fails and we move on).
void AmneziawgFlutterPlugin::CleanupStaleTunnels() {
  if (!service_name_.empty()) StopAndRemoveService(service_name_);
  // Well-known default interface name used by the Dart layer.
  for (const wchar_t* known : { L"mirrorspeed" }) {
    if (service_name_ != known) StopAndRemoveService(known);
  }
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
    if (name.empty()) name = "mirrorspeed";
    // Adapter description shown in ipconfig / network connections. Localized by
    // the Dart layer; defaults to a neutral self-branded string (never expose
    // "WireGuard Tunnel").
    std::string desc = get_str("localizedDescription");
    tunnel_description_ = Utf8ToWide(desc.empty() ? "MirrorSpeed VPN" : desc);
    Initialize(name, std::move(result));

  } else if (method == "start") {
    std::string conf        = get_str("wgQuickConfig");
    std::string server_addr = get_str("serverAddress");
    // The tunnel name was set during initialize; fall back to "mirrorspeed"
    std::string svc_name = service_name_.empty()
                               ? "mirrorspeed"
                               : WideToUtf8(service_name_);
    if (conf.empty()) {
      result->Error("MISSING_ARGS", "wgQuickConfig is required", nullptr);
      return;
    }
    // Installing/starting the tunnel service blocks for seconds (SCM stop+purge,
    // WFP setup, adapter creation). Run it off the platform thread so the UI
    // never freezes; StartTunnel owns the result and replies when done.
    std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> r(result.release());
    std::thread([this, conf, svc_name, r]() mutable {
      StartTunnel(conf, svc_name, r);
    }).detach();

  } else if (method == "stop") {
    std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> r(result.release());
    std::thread([this, r]() mutable {
      StopTunnel(r);
    }).detach();

  } else if (method == "stage") {
    GetStage(std::move(result));

  } else if (method == "transfer") {
    GetTransfer(std::move(result));

  } else if (method == "checkPermission") {
    // No special permission needed on Windows
    result->Success(flutter::EncodableValue());

  } else {
    result->NotImplemented();
  }
}

// -- Tunnel operations ------------------------------------------------------

// 从 wg 配置里解析 `DNS = a, b` 行，返回 IPv4 DNS 列表（宽字符，供 netsh）。
static std::vector<std::wstring> ParseDnsServers(const std::string& conf) {
  std::vector<std::wstring> out;
  std::istringstream ss(conf);
  std::string line;
  while (std::getline(ss, line)) {
    size_t b = line.find_first_not_of(" \t\r");
    if (b == std::string::npos) continue;
    std::string t = line.substr(b);
    if (t.rfind("DNS", 0) != 0) continue;          // 行首是 DNS
    size_t eq = t.find('=');
    if (eq == std::string::npos) continue;
    std::stringstream vs(t.substr(eq + 1));
    std::string ip;
    while (std::getline(vs, ip, ',')) {
      size_t s = ip.find_first_not_of(" \t\r");
      size_t e = ip.find_last_not_of(" \t\r");
      if (s == std::string::npos) continue;
      std::string v = ip.substr(s, e - s + 1);
      if (v.empty() || v.find(':') != std::string::npos) continue;  // 仅 IPv4
      out.push_back(Utf8ToWide(v));
    }
    break;   // 只取第一条 DNS 行
  }
  return out;
}

static void RunHidden(const std::wstring& cmdline) {
  STARTUPINFOW si{}; si.cb = sizeof(si);
  PROCESS_INFORMATION pi{};
  std::vector<wchar_t> buf(cmdline.begin(), cmdline.end());
  buf.push_back(L'\0');
  if (CreateProcessW(nullptr, buf.data(), nullptr, nullptr, FALSE,
                     CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi)) {
    WaitForSingleObject(pi.hProcess, 8000);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
  }
}

// 隧道服务不会把配置里的 DNS 应用到 wintun 适配器（适配器名 = 隧道名），
// 全局模式下 DNS 因此退回本地网卡 → 域名解析失败（隧道通但打不开网页）。
// 这里隧道起来后用 netsh 显式把 DNS 设到适配器上。适配器需片刻才出现，故重试。
static void ApplyAdapterDns(const std::wstring& iface, const std::vector<std::wstring>& dns) {
  if (dns.empty()) return;
  for (int attempt = 0; attempt < 6; ++attempt) {
    Sleep(500);
    RunHidden(L"netsh interface ipv4 set dnsservers name=\"" + iface +
              L"\" static " + dns[0] + L" primary");
    for (size_t i = 1; i < dns.size(); ++i) {
      RunHidden(L"netsh interface ipv4 add dnsservers name=\"" + iface +
                L"\" address=" + dns[i] + L" index=" + std::to_wstring(i + 1));
    }
  }
}

void AmneziawgFlutterPlugin::Initialize(
    const std::string& tunnel_name,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

  service_name_ = Utf8ToWide(tunnel_name);
  result->Success(flutter::EncodableValue());
}

void AmneziawgFlutterPlugin::StartTunnel(
    const std::string& wg_conf,
    const std::string& tunnel_name,
    std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

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
    // A partial start may have created the adapter + routes; tear it down so a
    // failed connection never leaves a dangling route table behind.
    StopAndRemoveService(service_name_);
    if (!conf_path_.empty()) { DeleteFileW(conf_path_.c_str()); conf_path_.clear(); }
    result->Error("START_FAILED",
                  "Failed to start AWG tunnel service: " + LastErrorString(),
                  nullptr);
    return;
  }

  result->Success(flutter::EncodableValue());
  SendStageEvent("connecting");
  StartMonitoring();

  // 隧道服务不自动设置适配器 DNS → 后台线程里 netsh 应用（带重试，等适配器就绪），
  // 不阻塞连接返回。否则全局模式域名解析失败、隧道通却打不开网页。
  auto dns = ParseDnsServers(wg_conf);
  if (!dns.empty()) {
    std::wstring ifname = service_name_;
    std::thread([ifname, dns]() { ApplyAdapterDns(ifname, dns); }).detach();
  }
}

void AmneziawgFlutterPlugin::StopTunnel(
    std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

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

// Total bytes (in+out) on the tunnel's WinTun adapter. These are the inner
// (decrypted) bytes the user actually moves — correct for usage metering, and
// they cover both direct and relay modes (the tunnel is always over WinTun).
// Returns -1 when the adapter isn't present (tunnel down).
void AmneziawgFlutterPlugin::GetTransfer(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  int64_t total = -1;
  PMIB_IF_TABLE2 table = nullptr;
  if (GetIfTable2(&table) == NO_ERROR && table) {
    const std::wstring want =
        service_name_.empty() ? L"mirrorspeed" : service_name_;
    for (ULONG i = 0; i < table->NumEntries; ++i) {
      const MIB_IF_ROW2& r = table->Table[i];
      if (want == r.Alias) {
        total = static_cast<int64_t>(r.InOctets + r.OutOctets);
        break;
      }
    }
    FreeMibTable(table);
  }
  result->Success(flutter::EncodableValue(total));
}

// -- Helpers ----------------------------------------------------------------

std::wstring AmneziawgFlutterPlugin::GetConfDir() const {
  wchar_t tmp[MAX_PATH];
  GetTempPathW(MAX_PATH, tmp);
  return std::wstring(tmp) + L"mirrorspeed";
}

// Find mirrorspeed_svc.exe next to the running executable or in its bin/ folder.
std::wstring AmneziawgFlutterPlugin::GetSvcExePath() const {
  wchar_t exePath[MAX_PATH];
  GetModuleFileNameW(nullptr, exePath, MAX_PATH);

  // Strip filename → directory
  std::wstring dir(exePath);
  auto slash = dir.rfind(L'\\');
  if (slash != std::wstring::npos) dir = dir.substr(0, slash);

  // Candidates: <exedir>\mirrorspeed_svc.exe, <exedir>\bin\mirrorspeed_svc.exe
  std::vector<std::wstring> candidates = {
      dir + L"\\mirrorspeed_svc.exe",
      dir + L"\\bin\\mirrorspeed_svc.exe",
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
// mirrorspeed_svc.exe <conf_path> is the expected interface.
bool AmneziawgFlutterPlugin::InstallAndStartService(
    const std::wstring& conf_path,
    const std::wstring& service_name) {

  std::wstring svc_exe = GetSvcExePath();
  if (svc_exe.empty()) {
    SetLastError(ERROR_FILE_NOT_FOUND);
    return false;
  }

  // Build binary path: svc.exe <conf> <adapter-description>
  // argv[2] lets the service set the WinTun adapter description (shown in
  // ipconfig) to our localized, self-branded string instead of "WireGuard Tunnel".
  std::wstring desc = tunnel_description_.empty() ? L"MirrorSpeed VPN" : tunnel_description_;
  std::wstring bin_path =
      L"\"" + svc_exe + L"\" \"" + conf_path + L"\" \"" + desc + L"\"";

  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_ALL_ACCESS);
  if (!scm) return false;

  // A freshly DeleteService'd tunnel may still linger in "marked for deletion"
  // state for a moment; CreateService/StartService then fail with
  // ERROR_SERVICE_MARKED_FOR_DELETE (1072) or ERROR_SERVICE_EXISTS (1073).
  // Retry the create+start a few times, giving the SCM time to purge the old
  // service, instead of failing the whole connection on a transient race.
  bool started = false;
  for (int attempt = 0; attempt < 20 && !started; ++attempt) {
    if (attempt > 0) Sleep(250);

    // Prefer a clean create. Only reuse an existing service if it's genuinely
    // there (not pending deletion).
    SC_HANDLE svc = CreateServiceW(
        scm,
        service_name.c_str(),
        L"MirrorSpeed VPN",
        SERVICE_ALL_ACCESS,
        SERVICE_WIN32_OWN_PROCESS,
        SERVICE_DEMAND_START,
        SERVICE_ERROR_NORMAL,
        bin_path.c_str(),
        nullptr, nullptr, nullptr, nullptr, nullptr);

    if (!svc) {
      DWORD err = GetLastError();
      if (err == ERROR_SERVICE_MARKED_FOR_DELETE) {
        continue;  // old instance still purging — wait and retry
      }
      if (err == ERROR_SERVICE_EXISTS) {
        // A healthy service with this name already exists — adopt it.
        svc = OpenServiceW(scm, service_name.c_str(), SERVICE_ALL_ACCESS);
        if (!svc) {
          if (GetLastError() == ERROR_SERVICE_MARKED_FOR_DELETE) continue;
          break;
        }
      } else {
        break;  // unrecoverable
      }
    }

    // Give the service its own (unrestricted) service SID. The tunnel scopes
    // its WFP firewall rules to the service's SID; without a service SID in the
    // process token the tunnel fails at "Enabling firewall rules: The specified
    // group does not exist." (firewall/helpers.go). This matches what WireGuard
    // for Windows does when installing its tunnel service.
    SERVICE_SID_INFO sidInfo{};
    sidInfo.dwServiceSidType = SERVICE_SID_TYPE_UNRESTRICTED;
    ChangeServiceConfig2W(svc, SERVICE_CONFIG_SERVICE_SID_INFO, &sidInfo);

    if (StartServiceW(svc, 0, nullptr)) {
      started = true;
    } else {
      DWORD err = GetLastError();
      if (err == ERROR_SERVICE_ALREADY_RUNNING) {
        started = true;
      } else if (err == ERROR_SERVICE_MARKED_FOR_DELETE) {
        // The instance we just created/opened is being torn down under us —
        // drop it and let the loop recreate a fresh one.
        CloseServiceHandle(svc);
        continue;
      }
    }
    CloseServiceHandle(svc);
  }

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
  CloseServiceHandle(svc);   // last handle closed → SCM can now purge it

  // DeleteService only *marks* the service for deletion; it isn't actually
  // removed until every open handle is closed AND it has stopped. If we return
  // before the purge completes, the next CreateService/StartService fails with
  // ERROR_SERVICE_MARKED_FOR_DELETE (1072). Poll until it's truly gone.
  for (int i = 0; i < 40; ++i) {
    SC_HANDLE probe = OpenServiceW(scm, service_name.c_str(), SERVICE_QUERY_STATUS);
    if (!probe) {
      if (GetLastError() == ERROR_SERVICE_DOES_NOT_EXIST) break;  // fully purged
      break;
    }
    CloseServiceHandle(probe);
    Sleep(100);
  }

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
