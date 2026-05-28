#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <string>

#include "flutter_window.h"
#include "utils.h"

// Register mirrorspeed:// and jinsuapp:// as URL protocols in the Windows
// registry so the OS knows to launch this app for those schemes.
static void RegisterUrlSchemes() {
  wchar_t exe_path[MAX_PATH] = {};
  GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
  std::wstring cmd = L"\"" + std::wstring(exe_path) + L"\" \"%1\"";

  const wchar_t* schemes[] = {L"mirrorspeed", L"jinsuapp"};
  for (const wchar_t* scheme : schemes) {
    std::wstring base = std::wstring(L"Software\\Classes\\") + scheme;

    HKEY key = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, base.c_str(), 0, nullptr,
                        REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr,
                        &key, nullptr) != ERROR_SUCCESS) continue;

    std::wstring desc = std::wstring(L"URL:") + scheme + L" Protocol";
    RegSetValueExW(key, nullptr, 0, REG_SZ,
                   reinterpret_cast<const BYTE*>(desc.c_str()),
                   static_cast<DWORD>((desc.size() + 1) * sizeof(wchar_t)));
    RegSetValueExW(key, L"URL Protocol", 0, REG_SZ,
                   reinterpret_cast<const BYTE*>(L""),
                   static_cast<DWORD>(sizeof(wchar_t)));

    HKEY cmd_key = nullptr;
    if (RegCreateKeyExW(key, L"shell\\open\\command", 0, nullptr,
                        REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr,
                        &cmd_key, nullptr) == ERROR_SUCCESS) {
      RegSetValueExW(cmd_key, nullptr, 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(cmd.c_str()),
                     static_cast<DWORD>((cmd.size() + 1) * sizeof(wchar_t)));
      RegCloseKey(cmd_key);
    }
    RegCloseKey(key);
  }
}

// Single-instance handling:
// When Windows launches a 2nd instance for an OAuth callback URL, forward
// the URL to the already-running window via WM_COPYDATA and exit.
static const wchar_t* kMutexName   = L"MirrorSpeedVPN_SingleInstance";
static const wchar_t* kWindowClass = L"FLUTTER_RUNNER_WIN32_WINDOW";
static const wchar_t* kWindowTitle = L"mirrorspeed_vpn";

struct CopyDataLink { wchar_t url[2048]; };

static bool ForwardToExistingInstance(const std::wstring& url) {
  HWND existing = FindWindowW(kWindowClass, kWindowTitle);
  if (!existing) return false;

  CopyDataLink data{};
  wcsncpy_s(data.url, url.c_str(), _TRUNCATE);

  COPYDATASTRUCT cds{};
  cds.dwData = WM_APP + 1;
  cds.cbData = sizeof(data);
  cds.lpData = &data;
  SendMessageW(existing, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&cds));
  return true;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Register URL schemes (idempotent)
  RegisterUrlSchemes();

  std::vector<std::string> args = GetCommandLineArguments();

  // Check if this launch was triggered by a deep-link URL
  std::wstring deep_link_url;
  if (!args.empty()) {
    const std::string& first = args[0];
    if (first.rfind("mirrorspeed://", 0) == 0 ||
        first.rfind("jinsuapp://",   0) == 0) {
      deep_link_url = std::wstring(first.begin(), first.end());
    }
  }

  // Single-instance: forward deep-link to existing window and exit
  HANDLE mutex = CreateMutexW(nullptr, TRUE, kMutexName);
  if (GetLastError() == ERROR_ALREADY_EXISTS && !deep_link_url.empty()) {
    ForwardToExistingInstance(deep_link_url);
    if (mutex) CloseHandle(mutex);
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments(std::move(args));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"mirrorspeed_vpn", origin, size)) {
    if (mutex) CloseHandle(mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (mutex) CloseHandle(mutex);
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
