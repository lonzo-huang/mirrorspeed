import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  // 界面按手机竖屏设计：与 Windows 版（windows/runner/main.cpp 420x860）一致用手机比例窗口，
  // 高度不超过屏幕可用区域（13" Mac 只有 ~800pt 高，860 放不下会被裁掉）。
  private static let phoneSize = NSSize(width: 420, height: 860)

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    let visible = (self.screen ?? NSScreen.main)?.visibleFrame
      ?? NSRect(origin: .zero, size: Self.phoneSize)
    let size = NSSize(width: Self.phoneSize.width,
                      height: min(Self.phoneSize.height, visible.height - 40))
    self.setContentSize(size)
    // 宽度只允许在手机范围内拉伸，避免拉成宽屏后布局变形。
    self.contentMinSize = NSSize(width: 360, height: 560)
    self.contentMaxSize = NSSize(width: 520, height: CGFloat.greatestFiniteMagnitude)
    self.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "MirrorSpeed VPN"
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    // 菜单栏（托盘）：节点列表与状态由 Dart 侧 lib/services/mac_tray.dart 推送。
    let trayChannel = FlutterMethodChannel(name: "mirrorspeed/tray",
                                           binaryMessenger: flutterViewController.engine.binaryMessenger)
    let tray = TrayController(channel: trayChannel, window: self)
    trayChannel.setMethodCallHandler { [weak tray] call, result in
      tray?.handle(call, result: result) ?? result(FlutterMethodNotImplemented)
    }
    self.tray = tray
    self.delegate = self

    super.awakeFromNib()
  }

  private var tray: TrayController?

  /// 点红叉不退出，只隐藏到菜单栏（隧道保持连接）。
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    self.orderOut(nil)
    // 隐藏后从 Dock 撤下图标，表现得像常驻菜单栏程序；从菜单栏打开时再恢复。
    NSApp.setActivationPolicy(.accessory)
    return false
  }

  func showFromTray() {
    tray?.showWindow()
  }
}
