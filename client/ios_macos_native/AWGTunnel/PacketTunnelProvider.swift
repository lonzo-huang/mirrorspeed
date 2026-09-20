import Foundation
import NetworkExtension
import os

/// MirrorSpeed 优质节点隧道扩展（AmneziaWG）。iOS 与 macOS 共用本文件。
///
/// 数据流：
///   App(AmneziawgFlutterPlugin) --providerConfiguration["wg_conf"](wg-quick 文本)-->
///   本扩展 startTunnel --> TunnelConfiguration(fromWgQuickConfig:) 解析(含 Jc/Jmin/Jmax/S1/S2/H1-H4)
///   --> WireGuardAdapter(vendored WireGuardKit) --> amneziawg-go(WireGuardKitGo.xcframework)。
///
/// WireGuardKit 源码取自 amneziawg-apple（MIT，见 COPYING），直接编进本 target，
/// C/Go 符号经 AWGTunnel-Bridging-Header.h 引入。
class PacketTunnelProvider: NEPacketTunnelProvider {

    private let log = OSLog(subsystem: "com.mirrorspeed.AWGTunnel", category: "tunnel")

    override init() {
        super.init()
        TunnelLog.name = "awg"
    }

    private lazy var adapter: WireGuardAdapter = {
        WireGuardAdapter(with: self) { [log] level, message in
            os_log("%{public}@", log: log, type: level == .error ? .error : .debug, message)
        }
    }()

    // MARK: - 生命周期

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        TunnelLog.log("startTunnel 被调用")
        guard
            let proto = protocolConfiguration as? NETunnelProviderProtocol,
            let wgConf = proto.providerConfiguration?["wg_conf"] as? String
        else {
            TunnelLog.log("❌ 配置里没有 wg_conf")
            completionHandler(TunnelError.missingConfig)
            return
        }

        let tunnelConfiguration: TunnelConfiguration
        do {
            tunnelConfiguration = try TunnelConfiguration(fromWgQuickConfig: wgConf, called: "mirrorspeed")
        } catch {
            TunnelLog.log("❌ 配置解析失败: \(error)")
            os_log("config parse failed: %{public}@", log: log, type: .error, "\(error)")
            completionHandler(TunnelError.invalidConfig("\(error)"))
            return
        }

        adapter.start(tunnelConfiguration: tunnelConfiguration) { [log] error in
            if let error = error {
                TunnelLog.log("❌ 内核启动失败: \(error)")
                os_log("adapter start failed: %{public}@", log: log, type: .error, "\(error)")
                completionHandler(error)
                return
            }
            TunnelLog.log("✅ 内核已启动")
            os_log("AmneziaWG tunnel started", log: log, type: .info)
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        TunnelLog.log("stopTunnel 原因码=\(reason.rawValue)")
        os_log("stopTunnel reason=%d", log: log, type: .info, reason.rawValue)
        adapter.stop { _ in
            completionHandler()
            #if os(macOS)
            // macOS 的 app extension 进程停隧道后不会自己退出；主动退出，
            // 下次 start 拿到干净的 Go 运行时（与 wireguard-apple 做法一致）。
            exit(0)
            #endif
        }
    }

    // MARK: - App ↔ 扩展消息

    /// "stats" → "rx,tx"：累计收发字节（取自 amneziawg-go 的 UAPI 运行时配置）。
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard String(data: messageData, encoding: .utf8) == "stats" else {
            completionHandler?(nil)
            return
        }
        adapter.getRuntimeConfiguration { settings in
            guard let settings = settings else {
                // 内核不在运行：主 App 会显示「扩展无响应」，这里记下来便于定位
                TunnelLog.log("⚠️ stats 查询时内核未运行（getRuntimeConfiguration 返回空）")
                completionHandler?(nil); return
            }
            var rx = 0, tx = 0, handshake = 0
            for line in settings.split(separator: "\n") {
                if line.hasPrefix("rx_bytes=") {
                    rx += Int(line.dropFirst("rx_bytes=".count)) ?? 0
                } else if line.hasPrefix("tx_bytes=") {
                    tx += Int(line.dropFirst("tx_bytes=".count)) ?? 0
                } else if line.hasPrefix("last_handshake_time_sec=") {
                    handshake = max(handshake, Int(line.dropFirst("last_handshake_time_sec=".count)) ?? 0)
                }
            }
            // 第三个字段是最后一次握手的 unix 时间（0 = 从未握手成功 = 隧道没真正建立）。
            // 老版本 App 只解析前两个字段，多出的字段会被忽略，兼容。
            completionHandler?(Data("\(rx),\(tx),\(handshake)".utf8))
        }
    }
}

enum TunnelError: LocalizedError {
    case missingConfig
    case invalidConfig(String)

    var errorDescription: String? {
        switch self {
        case .missingConfig:          return "missing wg_conf"
        case .invalidConfig(let msg): return "invalid wg_conf: \(msg)"
        }
    }
}
