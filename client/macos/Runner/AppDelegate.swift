import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // 关掉窗口不退出：VPN 常驻，靠菜单栏图标（TrayController）继续操作。
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  // 点 Dock 图标时把主窗口拉回来。
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      (NSApp.windows.first as? MainFlutterWindow)?.showFromTray()
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
