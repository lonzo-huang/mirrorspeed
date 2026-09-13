#ifndef RUNNER_TRAY_CONTROLLER_H_
#define RUNNER_TRAY_CONTROLLER_H_

#include <windows.h>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>
#include <vector>

// 托盘图标回调消息与 id（flutter_window.cpp 添加/移除图标时共用同一套值）。
constexpr UINT kTrayCallbackMessage = WM_APP + 1;
constexpr UINT kTrayIconId = 1;

// Windows 通知区（托盘）菜单控制器。与 Dart 侧 lib/services/desktop_tray.dart
// 经 MethodChannel "mirrorspeed/tray" 通信，是 macOS TrayController.swift 的对位实现：
//   Dart → 原生 `update`     ：状态 + 优质/免费节点列表，用于重建右键菜单
//   原生 → Dart `connect`{id|"auto"} / `connectFree`{id} / `disconnect` / `show`
// 菜单构建、命令分发、开机自启、tooltip 都在这里；托盘图标的增删和窗口消息路由
// 仍由 FlutterWindow 负责（持有 HWND 与 WndProc）。
class TrayController {
 public:
  TrayController(flutter::BinaryMessenger* messenger, HWND hwnd);
  ~TrayController();

  // 右键托盘图标：按当前状态弹出动态菜单。
  void ShowMenu();

  // 处理托盘菜单命令（来自 WM_COMMAND）。返回 true 表示已处理；
  // 通过 want_restore / want_quit 请求窗口层还原主窗口 / 真正退出。
  bool HandleCommand(UINT cmd_id, bool* want_restore, bool* want_quit);

  // 主窗口被唤出后通知 Dart 刷新一次 payload（对齐 macOS 的 show）。
  void InvokeShow();

 private:
  struct NodeItem {
    std::string id;
    std::wstring label;
  };

  void OnUpdate(const flutter::EncodableMap& args);
  void UpdateTooltip();
  void Invoke(const char* method, const std::string& id);
  bool LaunchAtLoginEnabled() const;
  void ToggleLaunchAtLogin();

  HWND hwnd_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  // ── 来自 Dart update 的状态 ──────────────────────────────────
  std::string status_ = "disconnected";  // disconnected/connecting/connected/disconnecting
  std::string kind_ = "none";            // premium/free/none
  std::string active_id_;
  std::wstring active_name_;
  bool auto_select_ = true;
  bool quota_exceeded_ = false;
  std::wstring elapsed_;
  std::wstring speed_;
  std::wstring trial_remaining_;
  std::vector<NodeItem> servers_;
  std::vector<NodeItem> free_nodes_;

  bool zh_ = true;  // 界面语言：跟随系统 UI 语言
};

#endif  // RUNNER_TRAY_CONTROLLER_H_
