#include "flutter_window.h"

#include <shellapi.h>
#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {
// System tray: clicking X hides to the tray; the tray menu offers Show/Exit.
constexpr UINT kTrayCallbackMessage = WM_APP + 1;
constexpr UINT kTrayIconId          = 1;
constexpr UINT kMenuShowId          = 1001;
constexpr UINT kMenuExitId          = 1002;
// CN labels via \u escapes: this target builds without /utf-8 and with /WX,
// so literal multibyte CJK in source would break the build.
const wchar_t* kTrayTip   = L"MirrorSpeed";
const wchar_t* kMenuShow  = L"显示主界面";  // Show main window
const wchar_t* kMenuExit  = L"退出";                    // Exit

void AddTrayIcon(HWND hwnd) {
  NOTIFYICONDATAW nid{};
  nid.cbSize           = sizeof(nid);
  nid.hWnd             = hwnd;
  nid.uID              = kTrayIconId;
  nid.uFlags           = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  nid.uCallbackMessage = kTrayCallbackMessage;
  nid.hIcon = LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
  wcscpy_s(nid.szTip, kTrayTip);
  Shell_NotifyIconW(NIM_ADD, &nid);
}

void RemoveTrayIcon(HWND hwnd) {
  NOTIFYICONDATAW nid{};
  nid.cbSize = sizeof(nid);
  nid.hWnd   = hwnd;
  nid.uID    = kTrayIconId;
  Shell_NotifyIconW(NIM_DELETE, &nid);
}

void RestoreWindow(HWND hwnd) {
  ShowWindow(hwnd, SW_SHOW);
  ShowWindow(hwnd, SW_RESTORE);
  SetForegroundWindow(hwnd);
}

void ShowTrayMenu(HWND hwnd) {
  POINT pt;
  GetCursorPos(&pt);
  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING, kMenuShowId, kMenuShow);
  AppendMenuW(menu, MF_STRING, kMenuExitId, kMenuExit);
  SetForegroundWindow(hwnd);  // 让菜单在点击别处时正确消失
  TrackPopupMenu(menu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, hwnd, nullptr);
  DestroyMenu(menu);
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  AddTrayIcon(GetHandle());   // 托盘常驻

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon(GetHandle());   // 真正退出时移除托盘图标

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;

    case WM_CLOSE:
      // 点右上角 X 不退出，最小化到托盘常驻。真正退出走托盘菜单"退出"。
      ShowWindow(hwnd, SW_HIDE);
      return 0;

    case kTrayCallbackMessage:
      // 左键单击/双击托盘图标 → 还原窗口；右键 → 弹出菜单。
      if (LOWORD(lparam) == WM_LBUTTONUP || LOWORD(lparam) == WM_LBUTTONDBLCLK) {
        RestoreWindow(hwnd);
      } else if (LOWORD(lparam) == WM_RBUTTONUP) {
        ShowTrayMenu(hwnd);
      }
      return 0;

    case WM_COMMAND: {
      const UINT cmd_id = static_cast<UINT>(LOWORD(wparam));
      if (cmd_id == kMenuShowId) {
        RestoreWindow(hwnd);
        return 0;
      }
      if (cmd_id == kMenuExitId) {
        DestroyWindow(hwnd);   // → WM_DESTROY → quit_on_close_ → PostQuitMessage
        return 0;
      }
      break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
