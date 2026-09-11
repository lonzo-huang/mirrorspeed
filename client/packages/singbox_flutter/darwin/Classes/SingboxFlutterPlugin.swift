import Foundation
import NetworkExtension
#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif

/// singbox_flutter 的 iOS / macOS 插件（App 侧，两平台共用本文件）。
///
/// 与 Android 保持完全一致的通道契约（见 client/lib/vpn/proxy_core_engine.dart）：
///   - MethodChannel `mirrorspeed/singbox`         : init / start / stop / stage / transferRxTx
///   - EventChannel  `mirrorspeed/singbox/stage`   : "connecting" / "connected" / "disconnecting" / "disconnected"
///
/// 真正跑 libbox(sing-box) 的是 Runner 里的 **SingboxTunnel** Network Extension
/// （源码 client/ios_macos_native/SingboxTunnel）。本插件只负责装配/启停它的
/// `NETunnelProviderManager`，并把系统隧道状态映射成 stage。
///
/// config（`start` 的 "config" 参数，SingboxConfig.build 生成的 sing-box JSON）通过
/// `NETunnelProviderProtocol.providerConfiguration["config"]` 传给扩展。
///
/// 优质节点（AmneziaWG）是另一个扩展、另一个 manager（两者都是 Go 运行时，不能同进程），
/// 所以这里按 providerBundleIdentifier 只认自己的 manager。
public class SingboxFlutterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

  /// 扩展 bundle id = 主 App bundle id + ".PacketTunnel"（见 setup_xcode_targets.rb）。
  static var tunnelBundleId: String {
    (Bundle.main.bundleIdentifier ?? "com.mirrorspeed.mirrorspeedVpn") + ".PacketTunnel"
  }

  private var eventSink: FlutterEventSink?
  private var manager: NETunnelProviderManager?
  private var statusObserver: NSObjectProtocol?
  private var lastStage: String?

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
    let messenger = registrar.messenger()
    #else
    let messenger = registrar.messenger
    #endif
    let control = FlutterMethodChannel(name: "mirrorspeed/singbox", binaryMessenger: messenger)
    let stage   = FlutterEventChannel(name: "mirrorspeed/singbox/stage", binaryMessenger: messenger)
    let instance = SingboxFlutterPlugin()
    registrar.addMethodCallDelegate(instance, channel: control)
    stage.setStreamHandler(instance)
    instance.observeStatus()
  }

  // MARK: - MethodChannel

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "init":
      loadManager { _, _ in result(nil) }

    case "start":
      guard let args = call.arguments as? [String: Any],
            let config = args["config"] as? String else {
        result(FlutterError(code: "bad_args", message: "missing config", details: nil)); return
      }
      start(config: config, result: result)

    case "stop":
      stop(result: result)

    case "stage":
      if manager == nil {
        loadManager { [weak self] _, _ in result(self?.currentStageName() ?? "disconnected") }
      } else {
        result(currentStageName())
      }

    case "transferRxTx":
      queryStats { rx, tx in result([rx, tx]) }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Tunnel lifecycle

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

  private func start(config: String, result: @escaping FlutterResult) {
    loadManager { [weak self] mgr, error in
      guard let self = self, let mgr = mgr else {
        result(FlutterError(code: "no_manager", message: error?.localizedDescription ?? "manager unavailable", details: nil)); return
      }
      let proto = NETunnelProviderProtocol()
      proto.providerBundleIdentifier = Self.tunnelBundleId
      // NE 要求非空 serverAddress，仅作展示。
      proto.serverAddress = "MirrorSpeed"
      proto.providerConfiguration = ["config": config]
      mgr.protocolConfiguration = proto
      mgr.localizedDescription = Self.displayName
      mgr.isEnabled = true
      mgr.saveToPreferences { saveErr in
        if let saveErr = saveErr {
          result(FlutterError(code: "save_failed", message: saveErr.localizedDescription, details: nil)); return
        }
        // saveToPreferences 后需重新 load 才能拿到已同步的对象再 start。
        mgr.loadFromPreferences { _ in
          DispatchQueue.main.async {
            do {
              try mgr.connection.startVPNTunnel()
              self.emitCurrent()
              result(nil)
            } catch {
              self.emit("disconnected")
              result(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil))
            }
          }
        }
      }
    }
  }

  private func stop(result: @escaping FlutterResult) {
    guard let mgr = manager else { result(nil); return }
    switch mgr.connection.status {
    case .connected, .connecting, .reasserting:
      mgr.connection.stopVPNTunnel()
    default:
      // 本来就没在跑：补发一次，免得 Dart 侧干等 disconnected。
      emit("disconnected")
    }
    result(nil)
  }

  /// 经 App↔扩展消息读取 tun 接口累计 [rx, tx] 字节；未连接/失败返回 [-1, -1]。
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

  /// 系统「设置 → VPN」里显示的名字：中文系统不出现 VPN 字样（与 Android 双壳一致）。
  private static var displayName: String {
    let zh = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") ?? false
    return zh ? "镜速加速 · 免费节点" : "MirrorSpeed · Free"
  }

  // MARK: - Status → stage

  private func observeStatus() {
    // object: nil —— 每次 loadAllFromPreferences 都是新的 connection 实例，只盯某个会漏。
    statusObserver = NotificationCenter.default.addObserver(
      forName: .NEVPNStatusDidChange, object: nil, queue: .main
    ) { [weak self] note in
      guard let self = self else { return }
      if let conn = note.object as? NEVPNConnection, conn === self.manager?.connection {
        self.emitCurrent()
      } else {
        self.loadManager { _, _ in }
      }
    }
  }

  private func currentStageName() -> String {
    switch manager?.connection.status {
    case .connecting, .reasserting: return "connecting"
    case .connected:                return "connected"
    case .disconnecting:            return "disconnecting"
    default:                        return "disconnected"
    }
  }

  private func emitCurrent() { emit(currentStageName()) }

  private func emit(_ name: String, force: Bool = false) {
    if !force && name == lastStage { return }
    lastStage = name
    eventSink?(name)
  }

  // MARK: - EventChannel

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    emit(currentStageName(), force: true)
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}
