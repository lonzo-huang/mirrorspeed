/// 隧道阶段。纯 sing-box 客户端自有定义（原先从 amneziawg 包导出）。
enum VpnStage { disconnected, connecting, connected, disconnecting }

/// VPN 引擎类型。现在只有 sing-box（优质+免费统一引擎）。
enum EngineKind { singbox }

/// 引擎启动参数。保留这层载体是为了以后再加引擎时不必改 VpnProvider 的调用签名；
/// 目前只有 sing-box 一个引擎，字段也只剩一个。
class EngineStartParams {
  /// 完整 sing-box 配置（所选节点 outbound + 路由规则 + DNS），见 SingboxConfig。
  final Map<String, dynamic>? singboxConfig;

  const EngineStartParams({this.singboxConfig});
}

/// 统一 VPN 引擎抽象。目前唯一实现是 [ProxyCoreEngine]（sing-box）。
/// 同一时刻只有一个引擎持有系统隧道（iOS/安卓单隧道限制），切换必须先 stop 再 start。
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
