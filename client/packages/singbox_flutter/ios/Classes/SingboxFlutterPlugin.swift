import Foundation
import NetworkExtension
#if os(iOS)
import Flutter
import UIKit
#else
import FlutterMacOS
import AppKit
#endif

/// singbox_flutter 的 iOS / macOS 插件（App 侧）。
///
/// 与 Android 保持完全一致的通道契约（见 client/lib/vpn/proxy_core_engine.dart）：
///   - MethodChannel `mirrorspeed/singbox`         : init / start / stop / stage / transferRxTx
///   - EventChannel  `mirrorspeed/singbox/stage`   : "connecting" / "connected" / "disconnecting" / "disconnected"
///
/// 真正跑 libbox(sing-box) 的是 **Network Extension**（NEPacketTunnelProvider），
/// 它是 host app 里一个独立的 target（见 ios/PacketTunnel / macos/PacketTunnel）。
/// 本插件只负责：装配/启动/停止 `NETunnelProviderManager`，并把系统隧道状态映射成 stage。
///
/// config（`start` 的 "config" 参数，SingboxConfig.build 生成的 sing-box JSON）通过
/// `NETunnelProviderProtocol.providerConfiguration["config"]` 传给扩展；扩展在
/// `startTunnel` 里把它交给 libbox。
public class SingboxFlutterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

  // App Group：改成你的（需与扩展、entitlements 一致）。用于共享统计文件等。
  static let kAppGroup = "group.com.mirrorspeed.app"
  // 扩展 bundle id：必须与 PacketTunnel target 的 bundle id 一致。
  static let kTunnelBundleId = "com.mirrorspeed.app.PacketTunnel"

  private var eventSink: FlutterEventSink?
  private var manager: NETunnelProviderManager?
  private var statusObserver: NSObjectProtocol?

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
  }

  // MARK: - MethodChannel

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "init":
      loadOrCreateManager { _ in result(nil) }

    case "start":
      guard let args = call.arguments as? [String: Any],
            let config = args["config"] as? String else {
        result(FlutterError(code: "bad_args", message: "missing config", details: nil)); return
      }
      start(config: config, result: result)

    case "stop":
      stop(result: result)

    case "stage":
      result(currentStageName())

    case "transferRxTx":
      // 可选：经 App Group 共享文件或 IPC 从扩展读取累计字节；骨架先返回未知。
      result([-1, -1])

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Tunnel lifecycle

  private func loadOrCreateManager(_ done: @escaping (NETunnelProviderManager?) -> Void) {
    NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
      guard let self = self else { return }
      let mgr = managers?.first ?? NETunnelProviderManager()
      self.manager = mgr
      self.observeStatus(mgr)
      done(mgr)
    }
  }

  private func start(config: String, result: @escaping FlutterResult) {
    loadOrCreateManager { [weak self] mgr in
      guard let self = self, let mgr = mgr else {
        result(FlutterError(code: "no_manager", message: "manager unavailable", details: nil)); return
      }
      let proto = NETunnelProviderProtocol()
      proto.providerBundleIdentifier = SingboxFlutterPlugin.kTunnelBundleId
      // NE 要求非空 serverAddress，仅作展示。
      proto.serverAddress = "MirrorSpeed"
      proto.providerConfiguration = ["config": config]
      mgr.protocolConfiguration = proto
      mgr.localizedDescription = "MirrorSpeed 免费节点"
      mgr.isEnabled = true
      mgr.saveToPreferences { saveErr in
        if let saveErr = saveErr {
          result(FlutterError(code: "save_failed", message: saveErr.localizedDescription, details: nil)); return
        }
        // saveToPreferences 后需重新 load 才能拿到已同步的对象再 start。
        mgr.loadFromPreferences { _ in
          do {
            self.emit("connecting")
            try mgr.connection.startVPNTunnel()
            result(nil)
          } catch {
            self.emit("disconnected")
            result(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }

  private func stop(result: @escaping FlutterResult) {
    guard let mgr = manager else { result(nil); return }
    emit("disconnecting")
    mgr.connection.stopVPNTunnel()
    result(nil)
  }

  // MARK: - Status → stage

  private func observeStatus(_ mgr: NETunnelProviderManager) {
    if let obs = statusObserver { NotificationCenter.default.removeObserver(obs) }
    statusObserver = NotificationCenter.default.addObserver(
      forName: .NEVPNStatusDidChange, object: mgr.connection, queue: .main
    ) { [weak self] _ in
      self?.emit(self?.currentStageName() ?? "disconnected")
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

  private func emit(_ name: String) {
    DispatchQueue.main.async { self.eventSink?(name) }
  }

  // MARK: - EventChannel

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    events(currentStageName())
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}
