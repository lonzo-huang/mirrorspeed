import NetworkExtension

// AmneziaWireGuardKit replaces WireGuardKit — same API, adds AWG obfuscation params.
// SPM: https://github.com/amnezia-vpn/amnezia-client (AmneziaWireGuardKit target)
// Or:  https://github.com/amnezia-vpn/AmneziaWireGuardKit
import AmneziaWireGuardKit

// MirrorSpeed VPN — iOS/macOS Network Extension (Packet Tunnel Provider)
// Bundle ID must match kProviderBundle in env.dart: com.mirrorspeed.vpn.network
class PacketTunnelProvider: NEPacketTunnelProvider {

    private var adapter: WireGuardAdapter?

    // ── Start tunnel ───────────────────────────────────────────────────────
    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard
            let proto    = protocolConfiguration as? NETunnelProviderProtocol,
            let confDict = proto.providerConfiguration,
            let confStr  = confDict["wg_conf"] as? String
        else {
            completionHandler(ProviderError.missingConfig)
            return
        }

        // AmneziaWireGuardKit's TunnelConfiguration parses AWG-specific fields
        // (Jc, Jmin, Jmax, S1, S2, H1-H4) in addition to standard WireGuard fields.
        let tunnelConf: TunnelConfiguration
        do {
            tunnelConf = try TunnelConfiguration(fromWgQuickConfig: confStr, called: "awg0")
        } catch {
            NSLog("[AWG] Config parse failed: \(error)")
            completionHandler(error)
            return
        }

        adapter = WireGuardAdapter(with: self) { _, message in
            NSLog("[AWG] \(message)")
        }

        adapter?.start(tunnelConfiguration: tunnelConf) { error in
            if let e = error {
                NSLog("[AWG] Start failed: \(e)")
            }
            completionHandler(error)
        }
    }

    // ── Stop tunnel ────────────────────────────────────────────────────────
    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        adapter?.stop { _ in completionHandler() }
    }

    // ── App <-> Extension messaging ────────────────────────────────────────
    override func handleAppMessage(
        _ messageData: Data,
        completionHandler: ((Data?) -> Void)?
    ) {
        // Extend here to return runtime stats (rx/tx bytes, last handshake, etc.)
        completionHandler?(nil)
    }
}

// ── Errors ─────────────────────────────────────────────────────────────────
enum ProviderError: Error {
    case missingConfig
}
