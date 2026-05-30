import Flutter
import UIKit
import NetworkExtension

// ── Channel names (must match Dart) ───────────────────────────────────────
private let kMethodChannel = "com.amneziawg.flutter/awgcontrol"
private let kEventChannel  = "com.amneziawg.flutter/awgstage"

public class AmneziawgFlutterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private var providerManager: NETunnelProviderManager?
    private var eventSink: FlutterEventSink?
    private var tunnelObserver: NSObjectProtocol?

    // ── Registration ───────────────────────────────────────────────────────
    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodCh = FlutterMethodChannel(name: kMethodChannel,
                                            binaryMessenger: registrar.messenger())
        let eventCh  = FlutterEventChannel(name: kEventChannel,
                                           binaryMessenger: registrar.messenger())
        let instance = AmneziawgFlutterPlugin()
        registrar.addMethodCallDelegate(instance, channel: methodCh)
        eventCh.setStreamHandler(instance)
    }

    // ── Method calls ───────────────────────────────────────────────────────
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "initialize":
            loadOrCreateManager(result: result)

        case "start":
            guard let conf = args?["wgQuickConfig"] as? String,
                  let bundle = args?["providerBundleIdentifier"] as? String
            else {
                result(FlutterError(code: "MISSING_ARGS", message: nil, details: nil))
                return
            }
            startTunnel(wgConf: conf, bundleId: bundle, result: result)

        case "stop":
            stopTunnel(result: result)

        case "stage":
            result(currentStageString())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ── StreamHandler ──────────────────────────────────────────────────────
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        observeTunnelStatus()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        if let obs = tunnelObserver { NotificationCenter.default.removeObserver(obs) }
        eventSink = nil
        return nil
    }

    // ── Private ────────────────────────────────────────────────────────────

    private func loadOrCreateManager(result: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error {
                result(FlutterError(code: "LOAD_FAILED", message: error.localizedDescription, details: nil))
                return
            }
            self.providerManager = managers?.first ?? NETunnelProviderManager()
            result(nil)
        }
    }

    private func startTunnel(wgConf: String, bundleId: String, result: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            let mgr = managers?.first ?? NETunnelProviderManager()

            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = bundleId
            proto.providerConfiguration    = ["wg_conf": wgConf]
            proto.serverAddress            = "AmneziaWG"

            mgr.protocolConfiguration = proto
            mgr.localizedDescription  = "MirrorSpeed VPN"
            mgr.isEnabled             = true

            mgr.saveToPreferences { error in
                if let e = error {
                    result(FlutterError(code: "SAVE_FAILED", message: e.localizedDescription, details: nil))
                    return
                }
                do {
                    try mgr.connection.startVPNTunnel()
                    self.providerManager = mgr
                    self.observeTunnelStatus()
                    result(nil)
                } catch {
                    result(FlutterError(code: "START_FAILED", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    private func stopTunnel(result: @escaping FlutterResult) {
        providerManager?.connection.stopVPNTunnel()
        result(nil)
    }

    private func observeTunnelStatus() {
        if let obs = tunnelObserver { NotificationCenter.default.removeObserver(obs) }
        tunnelObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.eventSink?(self?.currentStageString())
        }
    }

    private func currentStageString() -> String {
        switch providerManager?.connection.status {
        case .connected:     return "connected"
        case .connecting:    return "connecting"
        case .disconnecting: return "disconnecting"
        case .disconnected:  return "disconnected"
        case .invalid:       return "error"
        case .reasserting:   return "connecting"
        default:             return "no_connection"
        }
    }
}
