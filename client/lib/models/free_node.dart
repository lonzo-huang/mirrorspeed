/// 共享(免费机场)节点。由订阅源解析而来，`outbound` 是可直接塞进 sing-box
/// 配置 outbounds 的 map（端上零二次解析）。
class FreeNode {
  final String fingerprint;   // 去重指纹
  final String protocol;      // vless / trojan / ss / vmess / hysteria2 / anytls
  final String name;          // 展示名（订阅里 # 备注，已 urldecode）
  final String server;
  final int    port;
  final Map<String, dynamic> outbound;   // sing-box outbound JSON

  const FreeNode({
    required this.fingerprint,
    required this.protocol,
    required this.name,
    required this.server,
    required this.port,
    required this.outbound,
  });
}
