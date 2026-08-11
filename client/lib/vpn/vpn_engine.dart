import 'package:amneziawg_flutter/amneziawg_flutter.dart' show VpnStage;
export 'package:amneziawg_flutter/amneziawg_flutter.dart' show VpnStage;

/// VPN 引擎类型。节点按 tier 选引擎：付费/优质 → amneziawg；共享/免费机场 → singbox。
enum EngineKind { amneziawg, singbox }

/// 引擎启动参数。不同引擎读各自需要的字段，用一个统一载体，避免每加一个引擎就改
/// VpnProvider 的调用签名。
///   - AmneziaWG：serverAddress / wgQuickConfig / providerBundle
///   - sing-box（阶段 2）：singboxConfig（完整 JSON，含所选节点 outbound + 路由规则）
class EngineStartParams {
  // ── AmneziaWG ──
  final String? serverAddress;
  final String? wgQuickConfig;
  final String? providerBundle;
  // ── sing-box ──
  final Map<String, dynamic>? singboxConfig;

  const EngineStartParams({
    this.serverAddress,
    this.wgQuickConfig,
    this.providerBundle,
    this.singboxConfig,
  });
}

/// 统一 VPN 引擎抽象。现有 AmneziaWG 逻辑收进 [AmneziaWgEngine]；sing-box 之后作为
/// 第二个实现接入。同一时刻只有一个引擎持有系统隧道（iOS/安卓单隧道限制），
/// 切换引擎必须先 stop 旧的再 start 新的。
abstract class VpnEngine {
  EngineKind get kind;

  /// App 启动时一次性初始化（原生侧准备隧道适配器等）。
  Future<void> initialize();

  /// 隧道阶段事件流（connecting/connected/disconnecting/disconnected）。
  Stream<VpnStage> get stageStream;

  /// 查询当前阶段（冷启动采纳已运行隧道时用）。
  Future<VpnStage> stage();

  /// 建立隧道。
  Future<void> start(EngineStartParams params);

  /// 拆除隧道。
  Future<void> stop();

  /// 读取隧道累计 [rx, tx] 字节（用量计量）；不支持/未连接返回 [-1, -1]。
  Future<List<int>> transferRxTx();
}
