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

    /// 把 NSError 的域/代码一并带出来，便于定位（NE 的 localizedDescription 太笼统）。
    static func describe(_ error: Error) -> String {
        let e = error as NSError
        var msg = "\(e.localizedDescription) [\(e.domain) code=\(e.code)]"
        if let reason = e.localizedFailureReason { msg += " reason=\(reason)" }
        if let underlying = e.userInfo[NSUnderlyingErrorKey] as? NSError {
            msg += " under=\(underlying.domain)/\(underlying.code)"
        }
        NSLog("[AWG] %@", msg)
        return msg
    }

    // ── Manager ────────────────────────────────────────────────────────────

    /// 找到（或新建）属于 AWGTunnel 扩展的 manager。
    /// 防重入：loadAllFromPreferences 是异步的，重复调用会堆出大量 manager 实例。
    private var loading = false
    private var pending: [(NETunnelProviderManager?, Error?) -> Void] = []

    private func loadManager(_ done: @escaping (NETunnelProviderManager?, Error?) -> Void) {
        if loading { pending.append(done); return }
        loading = true
        let bundleId = Self.tunnelBundleId
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loading = false
                let queued = self.pending
                self.pending = []
                if let error = error {
                    done(nil, error)
                    queued.forEach { $0(nil, error) }
                    return
                }
                let mineAll = (managers ?? []).filter {
                    ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == bundleId
                }
                // 去重：历史上并发保存可能留下多条同名配置（系统会自动改名成「… 2」），
                // 多条同 bundle id 的配置会互相干扰导致连接失败。只留第一条，其余删掉。
                if mineAll.count > 1 {
                    for extra in mineAll.dropFirst() {
                        extra.removeFromPreferences { _ in }
                    }
                }
                let mine = mineAll.first
                let mgr = mine ?? self.manager ?? NETunnelProviderManager()
                self.manager = mgr
                done(mgr, nil)
                queued.forEach { $0(mgr, nil) }
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
                    result(FlutterError(code: "SAVE_FAILED", message: Self.describe(e), details: nil))
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
                            result(FlutterError(code: "START_FAILED",
                                                message: Self.describe(error),
                                                details: nil))
                        }
                    }
                }
            }
        }
    }

    private func stopTunnel(result: @escaping FlutterResult) {
        guard let mgr = manager else {
            // 还没加载过配置 = 肯定没在跑；强制回 disconnected，免得 Dart 干等。
            lastStage = nil
            emitCurrent()
            result(nil); return
        }
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
            // 只处理「自己这条隧道」的通知。
            // 切勿在这里调 loadAllFromPreferences 刷新：加载本身又会派发
            // NEVPNStatusDidChange，会形成 加载→通知→加载 的无限递归，
            // 几十秒就能造出上万个 NETunnelProviderManager 把内存吃光。
            guard let conn = note.object as? NEVPNConnection,
                  conn === self.manager?.connection else { return }
            self.emitCurrent()
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
