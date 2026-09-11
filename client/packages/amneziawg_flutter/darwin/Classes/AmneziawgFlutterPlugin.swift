import Foundation
import NetworkExtension
#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif

// ── Channel names (must match Dart) ───────────────────────────────────────
private let kMethodChannel = "com.amneziawg.flutter/awgcontrol"
private let kEventChannel  = "com.amneziawg.flutter/awgstage"

/// amneziawg_flutter 的 iOS / macOS 插件（App 侧，两平台共用本文件）。
///
/// 真正跑 amneziawg-go 的是 Runner 里的 **AWGTunnel** Network Extension
/// （源码 client/ios_macos_native/AWGTunnel）。本插件只负责装配/启停它的
/// `NETunnelProviderManager`，并把系统隧道状态映射成 stage 字符串。
///
/// 注意：sing-box（免费节点）是另一个扩展、另一个 manager。两者都是 Go 运行时，
/// 不能同进程，所以这里必须按 providerBundleIdentifier 找「自己的」manager，
/// 不能像旧骨架那样取 `managers.first`（会拿到 sing-box 的）。
public class AmneziawgFlutterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    /// 扩展 bundle id = 主 App bundle id + ".AWGTunnel"（见 setup_xcode_targets.rb）。
    /// Dart 传来的 providerBundleIdentifier（env.dart kProviderBundle）是历史值，不采用，
    /// 这样改主 bundle id 时无需同步 Dart。
    static var tunnelBundleId: String {
        (Bundle.main.bundleIdentifier ?? "com.mirrorspeed.mirrorspeedVpn") + ".AWGTunnel"
    }

    private var manager: NETunnelProviderManager?
    private var eventSink: FlutterEventSink?
    private var statusObserver: NSObjectProtocol?
    private var lastStage: String?

    // ── Registration ───────────────────────────────────────────────────────
    public static func register(with registrar: FlutterPluginRegistrar) {
        #if os(iOS)
        let messenger = registrar.messenger()
        #else
        let messenger = registrar.messenger
        #endif
        let methodCh = FlutterMethodChannel(name: kMethodChannel, binaryMessenger: messenger)
        let eventCh  = FlutterEventChannel(name: kEventChannel, binaryMessenger: messenger)
        let instance = AmneziawgFlutterPlugin()
        registrar.addMethodCallDelegate(instance, channel: methodCh)
        eventCh.setStreamHandler(instance)
        instance.observeStatus()
    }

    // ── Method calls ───────────────────────────────────────────────────────
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "initialize":
            let desc = args?["localizedDescription"] as? String
            loadManager { [weak self] mgr, err in
                if let err = err {
                    result(FlutterError(code: "LOAD_FAILED", message: err.localizedDescription, details: nil))
                    return
                }
                if let desc = desc { self?.tunnelDescription = desc }
                _ = mgr
                result(nil)
            }

        case "start":
            guard let conf = args?["wgQuickConfig"] as? String else {
                result(FlutterError(code: "MISSING_ARGS", message: "wgQuickConfig", details: nil))
                return
            }
            startTunnel(wgConf: conf, serverAddress: args?["serverAddress"] as? String, result: result)

        case "stop":
            stopTunnel(result: result)

        case "stage":
            // 冷启动采纳已运行隧道时会先调 stage：没 load 过就先 load。
            if manager == nil {
                loadManager { [weak self] _, _ in result(self?.currentStage()) }
            } else {
                result(currentStage())
            }

        case "transfer":
            queryStats { rx, tx in result(rx < 0 ? -1 : rx + tx) }

        case "transferRxTx":
            queryStats { rx, tx in result([rx, tx]) }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// 系统「设置 → VPN」里显示的名字（Dart initialize 传入的本地化描述）。
    private var tunnelDescription = "MirrorSpeed VPN"

    // ── StreamHandler ──────────────────────────────────────────────────────
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        lastStage = nil
        emitCurrent()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    // ── Manager ────────────────────────────────────────────────────────────

    /// 找到（或新建）属于 AWGTunnel 扩展的 manager。
    private func loadManager(_ done: @escaping (NETunnelProviderManager?, Error?) -> Void) {
        let bundleId = Self.tunnelBundleId
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error { done(nil, error); return }
                let mine = managers?.first {
                    ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == bundleId
                }
                let mgr = mine ?? self.manager ?? NETunnelProviderManager()
                self.manager = mgr
                done(mgr, nil)
                self.emitCurrent()
            }
        }
    }

    private func startTunnel(wgConf: String, serverAddress: String?, result: @escaping FlutterResult) {
        loadManager { [weak self] mgr, error in
            guard let self = self, let mgr = mgr else {
                result(FlutterError(code: "LOAD_FAILED", message: error?.localizedDescription, details: nil))
                return
            }
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = Self.tunnelBundleId
            proto.providerConfiguration    = ["wg_conf": wgConf]
            // NE 要求非空 serverAddress，仅用于系统设置里展示。
            proto.serverAddress            = (serverAddress?.isEmpty == false) ? serverAddress! : "MirrorSpeed"

            mgr.protocolConfiguration = proto
            mgr.localizedDescription  = self.tunnelDescription
            mgr.isEnabled             = true

            mgr.saveToPreferences { error in
                if let e = error {
                    result(FlutterError(code: "SAVE_FAILED", message: e.localizedDescription, details: nil))
                    return
                }
                // save 之后必须重新 load，否则首次 start 会报 "configuration is stale"。
                mgr.loadFromPreferences { _ in
                    DispatchQueue.main.async {
                        do {
                            try mgr.connection.startVPNTunnel()
                            self.emitCurrent()
                            result(nil)
                        } catch {
                            result(FlutterError(code: "START_FAILED", message: error.localizedDescription, details: nil))
                        }
                    }
                }
            }
        }
    }

    private func stopTunnel(result: @escaping FlutterResult) {
        guard let mgr = manager else { result(nil); return }
        switch mgr.connection.status {
        case .connected, .connecting, .reasserting:
            mgr.connection.stopVPNTunnel()
        default:
            // 本来就没在跑：补发一次当前状态，免得 Dart 侧干等 disconnected。
            lastStage = nil
            emitCurrent()
        }
        result(nil)
    }

    /// 经 App↔扩展消息读取累计 [rx, tx] 字节（扩展从 amneziawg-go 运行时配置里取）。
    private func queryStats(_ done: @escaping (Int, Int) -> Void) {
        guard let session = manager?.connection as? NETunnelProviderSession,
              session.status == .connected else { done(-1, -1); return }
        do {
            try session.sendProviderMessage(Data("stats".utf8)) { data in
                DispatchQueue.main.async {
                    guard let data = data,
                          let s = String(data: data, encoding: .utf8) else { done(-1, -1); return }
                    let parts = s.split(separator: ",").compactMap { Int($0) }
                    parts.count == 2 ? done(parts[0], parts[1]) : done(-1, -1)
                }
            }
        } catch {
            done(-1, -1)
        }
    }

    // ── Status → stage ─────────────────────────────────────────────────────

    private func observeStatus() {
        // object: nil —— loadAllFromPreferences 每次都会生成新的 connection 实例，
        // 只盯某个实例会漏通知。收到任何 VPN 状态变化都重新读「自己的」manager 状态。
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            if let conn = note.object as? NEVPNConnection, conn === self.manager?.connection {
                self.emitCurrent()
            } else {
                // 其它 connection 实例（或 sing-box 的 manager）变化：重新 load 自己的再报。
                self.loadManager { _, _ in }
            }
        }
    }

    private func emitCurrent() {
        let s = currentStage()
        guard s != lastStage else { return }
        lastStage = s
        eventSink?(s)
    }

    private func currentStage() -> String {
        guard let mgr = manager else { return "disconnected" }
        switch mgr.connection.status {
        case .connected:                return "connected"
        case .connecting, .reasserting: return "connecting"
        case .disconnecting:            return "disconnecting"
        case .disconnected:             return "disconnected"
        case .invalid:                  return "disconnected"
        @unknown default:               return "no_connection"
        }
    }
}
