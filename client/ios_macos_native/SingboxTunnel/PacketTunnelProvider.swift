import Foundation
import Libbox
import Network
import NetworkExtension
import os

/// MirrorSpeed 免费/共享节点隧道扩展（sing-box / libbox 1.13）。iOS 与 macOS 共用本文件。
///
/// 数据流（与 Android SingboxVpnService 同构）：
///   App(SingboxFlutterPlugin) --providerConfiguration["config"](sing-box JSON)-->
///   本扩展 startTunnel --> LibboxSetup --> LibboxNewCommandServer(handler, platform)
///   --> startOrReloadService(config) --> libbox 回调 openTun，我们装配
///   NEPacketTunnelNetworkSettings 并把系统 utun fd 交回。
///
/// 平台接口实现参照 sing-box 官方 Apple 客户端（sing-box-for-apple 的
/// ExtensionPlatformInterface），按 1.13.18 的 API 精简。
class PacketTunnelProvider: NEPacketTunnelProvider {

  let log = OSLog(subsystem: "com.mirrorspeed.SingboxTunnel", category: "tunnel")

  private var server: LibboxCommandServer?
  private var platform: SingboxPlatform?
  private static var didSetup = false

  /// openTun 后记下的 utun 接口名，用于读收发字节。
  var tunName: String?

  // MARK: - 生命周期

  override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
    guard
      let proto = protocolConfiguration as? NETunnelProviderProtocol,
      let config = proto.providerConfiguration?["config"] as? String
    else {
      completionHandler(SingboxTunnelError("missing sing-box config"))
      return
    }

    // startOrReloadService 会同步回调 openTun，而 openTun 要等 setTunnelNetworkSettings
    // 的回调 —— 放后台线程，别堵住 NE 的调用线程。
    DispatchQueue.global(qos: .userInitiated).async { [self] in
      do {
        try setupLibboxOnce()
        // 规则集（geoip-cn / geosite-cn）随扩展打包，Dart 侧用占位符写路径，
        // 这里换成本扩展 bundle 里的真实路径（Dart 不知道 bundle 路径，也不该知道）。
        let config = Self.resolveRuleSetPaths(config)

        var err: NSError?
        LibboxCheckConfig(config, &err)
        if let err = err { throw err }

        let platform = SingboxPlatform(self)
        guard let server = LibboxNewCommandServer(platform, platform, &err) else {
          throw err ?? SingboxTunnelError("LibboxNewCommandServer failed")
        }
        // 不调 server.start()：那只是给外部 UI 用的 gRPC 控制口（unix socket），
        // 本 App 经 NETunnelProviderSession 消息通信，用不上。
        try server.startOrReloadService(config, options: LibboxOverrideOptions())
        self.platform = platform
        self.server = server
        os_log("sing-box started", log: log, type: .info)
        completionHandler(nil)
      } catch {
        os_log("sing-box start failed: %{public}@", log: log, type: .error, error.localizedDescription)
        closeServer()
        completionHandler(error)
      }
    }
  }

  override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
    os_log("stopTunnel reason=%d", log: log, type: .info, reason.rawValue)
    closeServer()
    completionHandler()
    #if os(macOS)
    // macOS app extension 停隧道后进程常驻；退出以便下次拿到干净的 Go 运行时。
    exit(0)
    #endif
  }

  override func sleep(completionHandler: @escaping () -> Void) {
    server?.pause()
    completionHandler()
  }

  override func wake() {
    server?.wake()
  }

  /// "stats" → "rx,tx"：utun 接口累计收发字节（从 tun 的视角：in=下行，out=上行）。
  override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
    guard String(data: messageData, encoding: .utf8) == "stats",
          let name = tunName, let (rx, tx) = interfaceBytes(name) else {
      completionHandler?(nil)
      return
    }
    completionHandler?(Data("\(rx),\(tx)".utf8))
  }

  // MARK: - 内部

  /// Dart 侧的 sing-box 配置里，本地规则集路径写成 `$RULESET_DIR/xxx.srs`；
  /// 替换为扩展 bundle 内的实际资源目录。
  static func resolveRuleSetPaths(_ config: String) -> String {
    guard config.contains("$RULESET_DIR") else { return config }
    let dir = Bundle.main.resourcePath ?? Bundle.main.bundlePath
    return config.replacingOccurrences(of: "$RULESET_DIR", with: dir)
  }

  private func setupLibboxOnce() throws {
    if Self.didSetup { return }
    let fm = FileManager.default
    // 优先 App Group 容器（便于以后与主 App 共享日志），拿不到就用扩展自己的 caches。
    let group = "group." + ((Bundle.main.bundleIdentifier ?? "com.mirrorspeed.mirrorspeedVpn.PacketTunnel")
      .components(separatedBy: ".").dropLast().joined(separator: "."))
    let base = fm.containerURL(forSecurityApplicationGroupIdentifier: group)?
      .appendingPathComponent("Library/Caches/singbox", isDirectory: true)
      ?? fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("singbox", isDirectory: true)
    let work = base.appendingPathComponent("work", isDirectory: true)
    let temp = base.appendingPathComponent("temp", isDirectory: true)
    try fm.createDirectory(at: work, withIntermediateDirectories: true)
    try fm.createDirectory(at: temp, withIntermediateDirectories: true)

    let opts = LibboxSetupOptions()
    opts.basePath = base.path
    opts.workingPath = work.path
    opts.tempPath = temp.path
    var err: NSError?
    LibboxSetup(opts, &err)
    if let err = err { throw err }
    #if os(iOS)
    // iOS 的 NE 进程有 ~50MB 内存上限，开 libbox 的低内存模式（GC 更激进 + 软上限）。
    LibboxSetMemoryLimit(true)
    #endif
    Self.didSetup = true
  }

  private func closeServer() {
    platform?.reset()
    if let server = server {
      try? server.closeService()
      server.close()
    }
    server = nil
    platform = nil
    tunName = nil
  }
}

struct SingboxTunnelError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

/// 读取网络接口累计字节（getifaddrs 的 AF_LINK 项带 if_data）。
func interfaceBytes(_ name: String) -> (Int, Int)? {
  var head: UnsafeMutablePointer<ifaddrs>?
  guard getifaddrs(&head) == 0, let first = head else { return nil }
  defer { freeifaddrs(head) }
  var p: UnsafeMutablePointer<ifaddrs>? = first
  while let cur = p {
    let ifa = cur.pointee
    if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
       String(cString: ifa.ifa_name) == name,
       let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self) {
      return (Int(data.pointee.ifi_ibytes), Int(data.pointee.ifi_obytes))
    }
    p = ifa.ifa_next
  }
  return nil
}
