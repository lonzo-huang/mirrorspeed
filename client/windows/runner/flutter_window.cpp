#include "flutter_window.h"

#include <shellapi.h>
#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {
// System tray: clicking X hides to the tray. The dynamic tray menu (status,
// nodes, connect/disconnect, launch-at-login, show, quit) is built by
// TrayController from state pushed over the "mirrorspeed/tray" channel.
// kTrayCallbackMessage / kTrayIconId live in tray_controller.h so both agree.
const wchar_t* kTrayTip = L"MirrorSpeed";

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
  // 托盘菜单控制器：挂到 Flutter 引擎的 messenger 上，接收 Dart 推送的状态。
  tray_ = std::make_unique<TrayController>(
      flutter_controller_->engine()->messenger(), GetHandle());

  return true;
}

void FlutterWindow::OnDestroy() {
  tray_ = nullptr;              // 先拆通道（引擎还在），再销毁引擎
  RemoveTrayIcon(GetHandle());  // 真正退出时移除托盘图标

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
      // 左键单击/双击托盘图标 → 还原窗口；右键 → 弹出动态菜单。
      if (LOWORD(lparam) == WM_LBUTTONUP || LOWORD(lparam) == WM_LBUTTONDBLCLK) {
        RestoreWindow(hwnd);
        if (tray_) tray_->InvokeShow();
      } else if (LOWORD(lparam) == WM_RBUTTONUP) {
        if (tray_) tray_->ShowMenu();
      }
      return 0;

    case WM_COMMAND: {
      const UINT cmd_id = static_cast<UINT>(LOWORD(wparam));
      if (tray_) {
        bool want_restore = false, want_quit = false;
        if (tray_->HandleCommand(cmd_id, &want_restore, &want_quit)) {
          if (want_restore) RestoreWindow(hwnd);
          // 真正退出：DestroyWindow → WM_DESTROY → quit_on_close_ → PostQuitMessage
          if (want_quit) DestroyWindow(hwnd);
          return 0;
        }
      }
      break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
