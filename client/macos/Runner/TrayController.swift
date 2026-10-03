import Cocoa
import FlutterMacOS
import ServiceManagement

/// macOS 菜单栏（托盘）控制器。仅 macOS 有，不影响其它平台。
///
/// 与 Dart 侧 `lib/services/mac_tray.dart` 通过 MethodChannel `mirrorspeed/tray` 通信：
///   Dart → 原生 `update`  : 当前状态 + 优质节点列表，用来重建菜单
///   原生 → Dart `connect` : {"id": 节点 id 或 "auto"}
///   原生 → Dart `disconnect` / `show`
/// 「退出」直接终止 App（隧道由系统在进程退出时拆除）。
final class TrayController: NSObject, NSMenuDelegate {

  private let channel: FlutterMethodChannel
  private weak var window: NSWindow?
  private var statusItem: NSStatusItem?

  private var status = "disconnected"      // disconnected / connecting / connected / disconnecting
  private var activeId: String?
  private var activeName: String?
  private var autoSelect = true
  private var kind = "none"                  // premium / free / none：当前生效的隧道
  private var servers: [[String: Any]] = []  // {id, name, flag, latency}
  private var freeNodes: [[String: Any]] = []
  private var elapsed: String?               // 已连时长
  private var speed: String?                 // ↓x ↑y
  private var trialRemaining: String?        // 免费用户今日剩余
  private var quotaExceeded = false

  init(channel: FlutterMethodChannel, window: NSWindow?) {
    self.channel = channel
    self.window = window
    super.init()
    setupStatusItem()
    rebuildMenu()
  }

  private func setupStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = item.button {
      // SF Symbol：连上用实心盾牌，未连用虚线盾牌（模板图随明暗主题自动反色）。
      button.image = NSImage(systemSymbolName: "shield.lefthalf.filled",
                             accessibilityDescription: "MirrorSpeed")
      button.image?.isTemplate = true
      button.toolTip = "MirrorSpeed"
    }
    statusItem = item
  }

  // MARK: - Dart → 原生

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "update":
      let args = call.arguments as? [String: Any] ?? [:]
      status = args["status"] as? String ?? "disconnected"
      activeId = args["activeId"] as? String
      activeName = args["activeName"] as? String
      autoSelect = args["autoSelect"] as? Bool ?? true
      kind = args["kind"] as? String ?? "none"
      servers = args["servers"] as? [[String: Any]] ?? []
      freeNodes = args["freeNodes"] as? [[String: Any]] ?? []
      elapsed = args["elapsed"] as? String
      speed = args["speed"] as? String
      trialRemaining = args["trialRemaining"] as? String
      quotaExceeded = args["quotaExceeded"] as? Bool ?? false
      rebuildMenu()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - 菜单

  private func rebuildMenu() {
    let zh = (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("zh")
    func tr(_ c: String, _ e: String) -> String { zh ? c : e }

    let menu = NSMenu()
    menu.delegate = self

    // 状态行（不可点）
    let statusText: String
    switch status {
    case "connected":
      statusText = tr("已连接", "Connected") + (activeName.map { " · \($0)" } ?? "")
    case "connecting":     statusText = tr("连接中…", "Connecting…")
    case "disconnecting":  statusText = tr("断开中…", "Disconnecting…")
    default:               statusText = tr("未连接", "Not connected")
    }
    let statusRow = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
    statusRow.isEnabled = false
    menu.addItem(statusRow)

    // 用量：已连时长 / 实时速率 / 免费用户今日剩余时长
    func infoRow(_ text: String) {
      let row = NSMenuItem(title: text, action: nil, keyEquivalent: "")
      row.isEnabled = false
      row.attributedTitle = NSAttributedString(string: text, attributes: [
        .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
        .foregroundColor: NSColor.secondaryLabelColor,
      ])
      menu.addItem(row)
    }
    if let elapsed = elapsed, status == "connected" {
      infoRow(tr("已连接 ", "Uptime ") + elapsed)
    }
    if let speed = speed, status == "connected" {
      infoRow(speed)
    }
    if let remain = trialRemaining {
      infoRow(quotaExceeded
        ? tr("免费时长已用完", "Free time used up")
        : tr("今日剩余 ", "Remaining today ") + remain)
    }
    menu.addItem(.separator())

    // 优质节点（二级菜单：智能选择 + 各节点）
    let premium = NSMenuItem(title: tr("优质节点", "Premium nodes"), action: nil, keyEquivalent: "")
    let submenu = NSMenu()

    let auto = NSMenuItem(title: tr("智能选择", "Auto select"),
                          action: #selector(onConnectAuto), keyEquivalent: "")
    auto.target = self
    auto.state = (kind == "premium" && autoSelect && status == "connected") ? .on : .off
    submenu.addItem(auto)
    submenu.addItem(.separator())

    if servers.isEmpty {
      let empty = NSMenuItem(title: tr("暂无节点（请先登录）", "No nodes — sign in first"),
                             action: nil, keyEquivalent: "")
      empty.isEnabled = false
      submenu.addItem(empty)
    } else {
      for (i, s) in servers.enumerated() {
        let id = s["id"] as? String ?? ""
        let name = s["name"] as? String ?? id
        let flag = s["flag"] as? String ?? ""
        let latency = s["latency"] as? Int ?? -1
        var title = "\(flag) \(name)".trimmingCharacters(in: .whitespaces)
        if latency >= 0 { title += "  \(latency)ms" }
        let item = NSMenuItem(title: title, action: #selector(onConnectServer(_:)), keyEquivalent: "")
        item.target = self
        item.tag = i
        item.state = (kind == "premium" && !autoSelect && id == activeId) ? .on : .off
        submenu.addItem(item)
      }
    }
    premium.submenu = submenu
    menu.addItem(premium)

    // 免费节点（二级菜单，只放延迟最低的若干个；完整列表在主窗口）
    let freeItem = NSMenuItem(title: tr("免费节点", "Free nodes"), action: nil, keyEquivalent: "")
    let freeMenu = NSMenu()
    if freeNodes.isEmpty {
      let empty = NSMenuItem(title: tr("测速中或暂无可用节点", "Testing or none available"),
                             action: nil, keyEquivalent: "")
      empty.isEnabled = false
      freeMenu.addItem(empty)
    } else {
      for (i, n) in freeNodes.enumerated() {
        let id = n["id"] as? String ?? ""
        let name = n["name"] as? String ?? id
        let latency = n["latency"] as? Int ?? -1
        var title = name
        if latency >= 0 { title += "  \(latency)ms" }
        let item = NSMenuItem(title: title, action: #selector(onConnectFree(_:)), keyEquivalent: "")
        item.target = self
        item.tag = i
        item.state = (kind == "free" && id == activeId) ? .on : .off
        freeMenu.addItem(item)
      }
      freeMenu.addItem(.separator())
      let more = NSMenuItem(title: tr("更多节点…", "More nodes…"),
                            action: #selector(onShow), keyEquivalent: "")
      more.target = self
      freeMenu.addItem(more)
    }
    freeItem.submenu = freeMenu
    menu.addItem(freeItem)

    menu.addItem(.separator())
    if status == "connected" || status == "connecting" {
      let dis = NSMenuItem(title: tr("断开连接", "Disconnect"),
                           action: #selector(onDisconnect), keyEquivalent: "")
      dis.target = self
      menu.addItem(dis)
    }
    let login = NSMenuItem(title: tr("开机自启动", "Launch at login"),
                           action: #selector(onToggleLaunchAtLogin), keyEquivalent: "")
    login.target = self
    login.state = launchAtLoginEnabled ? .on : .off
    menu.addItem(login)

    let show = NSMenuItem(title: tr("打开主窗口", "Open MirrorSpeed"),
                          action: #selector(onShow), keyEquivalent: "")
    show.target = self
    menu.addItem(show)
    menu.addItem(.separator())
    let quit = NSMenuItem(title: tr("退出", "Quit"), action: #selector(onQuit), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)

    statusItem?.menu = menu
    applyIcon()
  }

  /// 菜单栏图标按状态区分：
  ///   未连接=空心盾牌，连接中/断开中=半填充（并轻微变淡），已连接=实心，
  ///   免费时长用完=带斜杠的盾牌。
  private func applyIcon() {
    let symbol: String
    var alpha: CGFloat = 1.0
    if quotaExceeded && status != "connected" {
      symbol = "shield.slash"
    } else {
      switch status {
      case "connected":                   symbol = "shield.fill"
      case "connecting", "disconnecting": symbol = "shield.lefthalf.filled"; alpha = 0.6
      default:                            symbol = "shield"
      }
    }
    let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MirrorSpeed")
    image?.isTemplate = true
    statusItem?.button?.image = image
    statusItem?.button?.alphaValue = alpha
    statusItem?.button?.toolTip = "MirrorSpeed" + (activeName.map { " · \($0)" } ?? "")
  }

  // MARK: - 开机自启动（macOS 13+ SMAppService）

  private var launchAtLoginEnabled: Bool {
    SMAppService.mainApp.status == .enabled
  }

  @objc private func onToggleLaunchAtLogin() {
    do {
      if launchAtLoginEnabled {
        try SMAppService.mainApp.unregister()
      } else {
        try SMAppService.mainApp.register()
      }
    } catch {
      NSLog("[tray] launch at login toggle failed: \(error)")
    }
    rebuildMenu()
  }

  // MARK: - 菜单动作 → Dart

  @objc private func onConnectAuto() {
    channel.invokeMethod("connect", arguments: ["id": "auto"])
  }

  @objc private func onConnectServer(_ sender: NSMenuItem) {
    guard sender.tag >= 0, sender.tag < servers.count,
          let id = servers[sender.tag]["id"] as? String else { return }
    channel.invokeMethod("connect", arguments: ["id": id])
  }

  @objc private func onConnectFree(_ sender: NSMenuItem) {
    guard sender.tag >= 0, sender.tag < freeNodes.count,
          let id = freeNodes[sender.tag]["id"] as? String else { return }
    channel.invokeMethod("connectFree", arguments: ["id": id])
  }

  @objc private func onDisconnect() {
    channel.invokeMethod("disconnect", arguments: nil)
  }

  @objc private func onShow() {
    showWindow()
  }

  @objc private func onQuit() {
    NSApp.terminate(nil)
  }

  func showWindow() {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
    channel.invokeMethod("show", arguments: nil)
  }
}
