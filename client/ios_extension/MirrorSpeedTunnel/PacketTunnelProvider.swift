import NetworkExtension
import WireGuardKit

// MirrorSpeed VPN — iOS Network Extension (Packet Tunnel Provider)
// Bundle ID 必须与 env.dart 中的 kProviderBundle 一致：com.mirrorspeed.vpn.network
class PacketTunnelProvider: NEPacketTunnelProvider {

    private var adapter: WireGuardAdapter?

    // ── 启动 VPN 隧道 ──────────────────────────────────────────
    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // wireguard_flutter 通过 protocolConfiguration.providerConfiguration 传入 wg-quick 格式的配置
        guard
            let proto    = protocolConfiguration as? NETunnelProviderProtocol,
            let confDict = proto.providerConfiguration,
            let confStr  = confDict["wg_conf"] as? String
        else {
            completionHandler(PacketTunnelError.missingConfig)
            return
        }

        let tunnelConf: TunnelConfiguration
        do {
            tunnelConf = try TunnelConfiguration(fromWgQuickConfig: confStr, called: "wg0")
        } catch {
            completionHandler(error)
            return
        }

        adapter = WireGuardAdapter(with: self) { _, message in
            NSLog("WireGuard: \(message)")
        }

        adapter?.start(tunnelConfiguration: tunnelConf) { error in
            completionHandler(error)
        }
    }

    // ── 停止 VPN 隧道 ──────────────────────────────────────────
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        adapter?.stop { _ in completionHandler() }
    }

    // ── 处理来自主 App 的消息 ──────────────────────────────────
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // 可通过此通道传递统计信息等
        completionHandler?(nil)
    }
}

enum PacketTunnelError: Error {
    case missingConfig
}
