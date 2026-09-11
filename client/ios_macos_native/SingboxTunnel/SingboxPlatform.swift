import Foundation
import Libbox
import Network
import NetworkExtension
import os

/// libbox 的平台接口 + CommandServer 回调（对应 Android SingboxVpnService 里的
/// PlatformInterface / CommandServerHandler 实现）。
final class SingboxPlatform: NSObject, LibboxPlatformInterfaceProtocol, LibboxCommandServerHandlerProtocol {

  private weak var tunnel: PacketTunnelProvider?
  private var nwMonitor: NWPathMonitor?

  init(_ tunnel: PacketTunnelProvider) {
    self.tunnel = tunnel
  }

  func reset() {
    nwMonitor?.cancel()
    nwMonitor = nil
  }

  // MARK: - openTun：按 libbox 的 TunOptions 装配 NEPacketTunnelNetworkSettings

  func openTun(_ options: LibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
    guard let options = options, let ret0_ = ret0_, let tunnel = tunnel else {
      throw SingboxTunnelError("openTun: bad arguments")
    }
    let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

    if options.getAutoRoute() {
      settings.mtu = NSNumber(value: options.getMTU())

      var dnsSettings: NEDNSSettings?
      if let dns = try? options.getDNSServerAddress().value, !dns.isEmpty {
        dnsSettings = NEDNSSettings(servers: [dns])
        settings.dnsSettings = dnsSettings
      }

      // IPv4
      var v4Addr: [String] = [], v4Mask: [String] = []
      if let it = options.getInet4Address() {
        while it.hasNext() { if let p = it.next() { v4Addr.append(p.address()); v4Mask.append(p.mask()) } }
      }
      let v4 = NEIPv4Settings(addresses: v4Addr, subnetMasks: v4Mask)
      var v4Routes: [NEIPv4Route] = []
      if let it = options.getInet4RouteAddress(), it.hasNext() {
        while it.hasNext() {
          if let p = it.next() { v4Routes.append(NEIPv4Route(destinationAddress: p.address(), subnetMask: p.mask())) }
        }
      } else {
        v4Routes.append(NEIPv4Route.default())
      }
      var v4Exclude: [NEIPv4Route] = []
      if let it = options.getInet4RouteExcludeAddress() {
        while it.hasNext() {
          if let p = it.next() { v4Exclude.append(NEIPv4Route(destinationAddress: p.address(), subnetMask: p.mask())) }
        }
      }
      v4.includedRoutes = v4Routes
      v4.excludedRoutes = v4Exclude
      settings.ipv4Settings = v4

      // IPv6（Dart 侧仅在系统确有全局 IPv6 时才给 tun 配 v6 地址）
      var v6Addr: [String] = [], v6Prefix: [NSNumber] = []
      if let it = options.getInet6Address() {
        while it.hasNext() { if let p = it.next() { v6Addr.append(p.address()); v6Prefix.append(NSNumber(value: p.prefix())) } }
      }
      if !v6Addr.isEmpty {
        let v6 = NEIPv6Settings(addresses: v6Addr, networkPrefixLengths: v6Prefix)
        var v6Routes: [NEIPv6Route] = []
        if let it = options.getInet6RouteAddress(), it.hasNext() {
          while it.hasNext() {
            if let p = it.next() {
              v6Routes.append(NEIPv6Route(destinationAddress: p.address(), networkPrefixLength: NSNumber(value: p.prefix())))
            }
          }
        } else {
          v6Routes.append(NEIPv6Route.default())
        }
        var v6Exclude: [NEIPv6Route] = []
        if let it = options.getInet6RouteExcludeAddress() {
          while it.hasNext() {
            if let p = it.next() {
              v6Exclude.append(NEIPv6Route(destinationAddress: p.address(), networkPrefixLength: NSNumber(value: p.prefix())))
            }
          }
        }
        v6.includedRoutes = v6Routes
        v6.excludedRoutes = v6Exclude
        settings.ipv6Settings = v6
      }

      // 非全局路由时，DNS 只接管匹配域（与 SFI 一致），否则系统 DNS 会绕开隧道。
      let hasDefault = v4Routes.contains { $0.destinationAddress == "0.0.0.0" && $0.destinationSubnetMask == "0.0.0.0" }
      if !hasDefault {
        dnsSettings?.matchDomains = [""]
        dnsSettings?.matchDomainsNoSearch = true
      }
    }

    if options.isHTTPProxyEnabled() {
      let proxy = NEProxySettings()
      let srv = NEProxyServer(address: options.getHTTPProxyServer(), port: Int(options.getHTTPProxyServerPort()))
      proxy.httpServer = srv
      proxy.httpsServer = srv
      settings.proxySettings = proxy
    }

    // setTunnelNetworkSettings 是异步回调；libbox 在自己的线程上同步等它。
    let sem = DispatchSemaphore(value: 0)
    var applyErr: Error?
    tunnel.setTunnelNetworkSettings(settings) { err in applyErr = err; sem.signal() }
    sem.wait()
    if let applyErr = applyErr { throw applyErr }

    // 取系统分配的 utun fd：先走 packetFlow 的私有 KVC（SFI 同法），不行再遍历 fd。
    var fd: Int32 = -1
    if let v = tunnel.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
      fd = v
    } else {
      fd = LibboxGetTunnelFileDescriptor()
    }
    if fd < 0 { throw SingboxTunnelError("utun file descriptor not found") }
    tunnel.tunName = utunName(fd)
    ret0_.pointee = fd
  }

  // MARK: - 其余平台接口

  func localDNSTransport() -> LibboxLocalDNSTransportProtocol? { nil }
  func usePlatformAutoDetectControl() -> Bool { false }
  func autoDetectControl(_ fd: Int32) throws {}
  func useProcFS() -> Bool { false }
  func underNetworkExtension() -> Bool { true }
  func includeAllNetworks() -> Bool { false }
  func readWIFIState() -> LibboxWIFIState? { nil }
  func systemCertificates() -> LibboxStringIteratorProtocol? { nil }
  func clearDNSCache() {}
  func send(_ notification: LibboxNotification?) throws {}

  func findConnectionOwner(_ ipProtocol: Int32, sourceAddress: String?, sourcePort: Int32,
                           destinationAddress: String?, destinationPort: Int32) throws -> LibboxConnectionOwner {
    // Apple NE 拿不到连接所属进程（分应用在 iOS/macOS 上走全局隧道）。
    throw SingboxTunnelError("findConnectionOwner not supported")
  }

  /// 默认网络监控：sing-box 的出站需要知道当前物理网卡（切 Wi-Fi/蜂窝时重连）。
  func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
    guard let listener = listener else { return }
    let monitor = NWPathMonitor()
    nwMonitor = monitor
    let first = DispatchSemaphore(value: 0)
    var signaled = false
    monitor.pathUpdateHandler = { path in
      Self.push(listener, path)
      if !signaled { signaled = true; first.signal() }
    }
    monitor.start(queue: DispatchQueue.global())
    _ = first.wait(timeout: .now() + 5)
  }

  func closeDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
    reset()
  }

  private static func push(_ listener: LibboxInterfaceUpdateListenerProtocol, _ path: Network.NWPath) {
    guard path.status != .unsatisfied, let iface = path.availableInterfaces.first else {
      listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
      return
    }
    listener.updateDefaultInterface(iface.name, interfaceIndex: Int32(iface.index),
                                    isExpensive: path.isExpensive, isConstrained: path.isConstrained)
  }

  func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
    guard let monitor = nwMonitor else { return InterfaceArray([]) }
    let path = monitor.currentPath
    if path.status == .unsatisfied { return InterfaceArray([]) }
    let list: [LibboxNetworkInterface] = path.availableInterfaces.map { it in
      let i = LibboxNetworkInterface()
      i.name = it.name
      i.index = Int32(it.index)
      switch it.type {
      case .wifi:          i.type = LibboxInterfaceTypeWIFI
      case .cellular:      i.type = LibboxInterfaceTypeCellular
      case .wiredEthernet: i.type = LibboxInterfaceTypeEthernet
      default:             i.type = LibboxInterfaceTypeOther
      }
      return i
    }
    return InterfaceArray(list)
  }

  // MARK: - CommandServerHandler

  func serviceStop() throws {
    // sing-box 内部要求停止（例如配置致命错误）→ 让系统拆隧道。
    tunnel?.cancelTunnelWithError(nil)
  }
  func serviceReload() throws {}
  func getSystemProxyStatus() throws -> LibboxSystemProxyStatus {
    let s = LibboxSystemProxyStatus()
    s.available = false
    s.enabled = false
    return s
  }
  func setSystemProxyEnabled(_ isEnabled: Bool) throws {}
  func writeDebugMessage(_ message: String?) {
    guard let message = message, let log = tunnel?.log else { return }
    os_log("%{public}@", log: log, type: .debug, message)
  }
}

private final class InterfaceArray: NSObject, LibboxNetworkInterfaceIteratorProtocol {
  private var iterator: IndexingIterator<[LibboxNetworkInterface]>
  private var nextValue: LibboxNetworkInterface?
  init(_ array: [LibboxNetworkInterface]) { iterator = array.makeIterator() }
  func hasNext() -> Bool { nextValue = iterator.next(); return nextValue != nil }
  func next() -> LibboxNetworkInterface? { nextValue }
}

/// utun fd → 接口名（getsockopt SYSPROTO_CONTROL / UTUN_OPT_IFNAME）。
private func utunName(_ fd: Int32) -> String? {
  var buf = [CChar](repeating: 0, count: Int(IFNAMSIZ))
  var len = socklen_t(buf.count)
  guard getsockopt(fd, 2 /* SYSPROTO_CONTROL */, 2 /* UTUN_OPT_IFNAME */, &buf, &len) == 0 else { return nil }
  return String(cString: buf)
}
