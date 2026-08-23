import NetworkExtension
import Libbox   // sing-box 的 Apple xcframework：Libbox.xcframework（见 README）
import os

/// MirrorSpeed 免费节点隧道扩展（NEPacketTunnelProvider）——真正运行 libbox(sing-box)。
///
/// iOS 与 macOS 共用本文件：把它同时加入 `PacketTunnel`（iOS）与
/// `PacketTunnelMac`（macOS）两个 Network Extension target 的编译源。
///
/// 数据流：
///   App(SingboxFlutterPlugin) --NETunnelProviderProtocol.providerConfiguration["config"]-->
///   本扩展 startTunnel --> LibboxNewService(config, self) --> libbox 建 tun 并转发。
///
/// 本类同时实现 LibboxPlatformInterfaceProtocol：libbox 需要宿主提供 openTun / 网络信息 /
/// 写日志等。核心是 `openTun`：据 libbox 的 TunOptions 装配 NEPacketTunnelNetworkSettings，
/// 应用后把系统分配的 utun fd 交回 libbox。
///
/// ⚠️ 骨架：标注 TODO 处需在 Mac + Xcode 上按实际 Libbox API 版本补全/校正
/// （Libbox 的方法签名随版本略有差异，以你集成的 xcframework 头文件为准）。
class PacketTunnelProvider: NEPacketTunnelProvider {

  private var boxService: LibboxBoxService?
  private let log = OSLog(subsystem: "com.mirrorspeed.app.PacketTunnel", category: "tunnel")

  // MARK: - 生命周期

  override func startTunnel(options: [String: NSObject]?,
                            completionHandler: @escaping (Error?) -> Void) {
    guard
      let proto = protocolConfiguration as? NETunnelProviderProtocol,
      let config = proto.providerConfiguration?["config"] as? String
    else {
      completionHandler(NSError(domain: "mirrorspeed", code: -1,
        userInfo: [NSLocalizedDescriptionKey: "missing sing-box config"]))
      return
    }

    // libbox 基础路径（缓存 / geo 资源）。用 App Group 容器便于与主 App 共享。
    let base = FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: "group.com.mirrorspeed.app")?
      .path ?? NSTemporaryDirectory()

    var setupErr: NSError?
    // TODO(Libbox 版本)：确认 LibboxSetup 参数签名（basePath, workingPath, tempPath, isTVOS）。
    LibboxSetup(base, base, NSTemporaryDirectory(), false)
    if let setupErr = setupErr {
      completionHandler(setupErr); return
    }

    var newErr: NSError?
    // 平台接口 self 提供 openTun 等回调。
    guard let service = LibboxNewService(config, self, &newErr), newErr == nil else {
      completionHandler(newErr ?? NSError(domain: "mirrorspeed", code: -2,
        userInfo: [NSLocalizedDescriptionKey: "LibboxNewService failed"]))
      return
    }
    boxService = service

    do {
      try service.start()
      os_log("sing-box service started", log: log, type: .info)
      completionHandler(nil)
    } catch {
      os_log("service start failed: %{public}@", log: log, type: .error, "\(error)")
      completionHandler(error)
    }
  }

  override func stopTunnel(with reason: NEProviderStopReason,
                           completionHandler: @escaping () -> Void) {
    try? boxService?.close()
    boxService = nil
    completionHandler()
  }
}

// MARK: - LibboxPlatformInterfaceProtocol
//
// libbox 通过这些回调向宿主索取能力。方法名/签名以你集成的 Libbox 头文件为准，
// 下列为 sing-box Apple 版常见形态，请对照校正（标 TODO 处）。
extension PacketTunnelProvider: LibboxPlatformInterfaceProtocol {

  /// 核心：按 libbox 给的 TunOptions 装配隧道网络设置，应用后返回 utun fd。
  func openTun(_ options: LibboxTunOptionsProtocol?, ret0_ error: NSErrorPointer) -> Int32 {
    guard let options = options else { return -1 }
    let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

    // IPv4 地址 / 路由
    do {
      let addr4 = try options.getInet4Address()        // TODO: 确认迭代器/字符串形态
      let v4 = NEIPv4Settings(addresses: [addr4.address], subnetMasks: [addr4.mask])
      v4.includedRoutes = [NEIPv4Route.default()]      // 全局路由；分应用在 iOS 上不适用
      settings.ipv4Settings = v4
    } catch { /* 无 v4 则跳过 */ }

    // IPv6（可选）
    do {
      let addr6 = try options.getInet6Address()
      let v6 = NEIPv6Settings(addresses: [addr6.address], networkPrefixLengths: [addr6.prefix])
      v6.includedRoutes = [NEIPv6Route.default()]
      settings.ipv6Settings = v6
    } catch {}

    // MTU
    settings.mtu = NSNumber(value: options.getMTU())

    // DNS（libbox 会在隧道内自建 DNS；这里指一个隧道内地址即可）
    let dns = NEDNSSettings(servers: ["127.0.0.1"])    // TODO: 取 options 提供的 DNS
    dns.matchDomains = [""]
    settings.dnsSettings = dns

    // 同步应用网络设置，然后抓取系统分配的 utun fd 交给 libbox。
    let sem = DispatchSemaphore(value: 0)
    var applyErr: Error?
    setTunnelNetworkSettings(settings) { err in applyErr = err; sem.signal() }
    sem.wait()
    if let applyErr = applyErr {
      error?.pointee = applyErr as NSError
      return -1
    }
    guard let fd = tunnelFileDescriptor else {
      error?.pointee = NSError(domain: "mirrorspeed", code: -3,
        userInfo: [NSLocalizedDescriptionKey: "utun fd not found"])
      return -1
    }
    return fd
  }

  // 以下为 libbox 平台接口的其余成员，按需返回默认值（骨架）。
  func usePlatformAutoDetectInterfaceControl() -> Bool { true }
  func autoDetectInterfaceControl(_ fd: Int32) throws {}
  func useProcFS() -> Bool { false }
  func writeLog(_ message: String?) { if let m = message { os_log("%{public}@", log: log, type: .debug, m) } }
  func clearDNSCache() {}
  // TODO: 视 Libbox 头文件补全其余可选方法（findConnectionOwner / packageName 等 iOS 多返回未实现）。
}

// MARK: - utun fd 抓取
//
// NEPacketTunnelProvider 不直接暴露 tun fd。setTunnelNetworkSettings 之后，
// 进程内会存在一个 name 以 "utun" 开头的 socket，遍历低位 fd 即可找到它。
private extension PacketTunnelProvider {
  var tunnelFileDescriptor: Int32? {
    var ctlInfo = ctl_info()
    // 常规做法：遍历 fd，用 getsockopt(UTUN_OPT_IFNAME) 读接口名判断是否 utun。
    let UTUN_OPT_IFNAME: Int32 = 2
    let SYSPROTO_CONTROL: Int32 = 2
    for fd: Int32 in 0...1024 {
      var buf = [CChar](repeating: 0, count: 128)
      var len = socklen_t(buf.count)
      let r = getsockopt(fd, SYSPROTO_CONTROL, UTUN_OPT_IFNAME, &buf, &len)
      if r == 0, String(cString: buf).hasPrefix("utun") {
        return fd
      }
    }
    _ = ctlInfo
    return nil
  }
}
