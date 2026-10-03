/// 优质节点的 sing-box 凭证与协议参数（`/api/mobile/configs` 的 `singbox` 块）。
///
/// 迁移期内此块可为空：为空表示该节点尚未开通 sing-box，客户端回退 AmneziaWG。
/// 三层协议对应现有的「快速 / 强力 / 超级」，任一层缺失即该模式不可选 ——
/// 阶段 1 只会下发 hysteria2 与 reality，ws 留到阶段 2（见
/// docs/singbox-migration.md §8.1）。
///
/// 设计原则：**客户端不内置任何默认值**（端口、SNI、跳跃范围全部来自后端），
/// 后端改参数即时生效，不用发版 —— iOS 发版要过审核，这一点尤其重要。
class SingboxPremium {
  /// VLESS 认证用，reality 与 ws 共用。按设备下发。
  final String uuid;
  /// Hysteria2 认证用。按设备下发。
  final String hy2Password;

  final Hysteria2Params? hysteria2;   // 快速
  final RealityParams?   reality;     // 强力
  final WsParams?        ws;          // 超级（阶段 2）

  const SingboxPremium({
    required this.uuid,
    required this.hy2Password,
    this.hysteria2,
    this.reality,
    this.ws,
  });

  static SingboxPremium? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final uuid = j['uuid'] as String?;
    final pwd  = j['hy2_password'] as String?;
    // 凭证缺失说明后端还没给这台设备发 —— 当作「未开通」回退 AWG，而不是半残运行。
    if (uuid == null || uuid.isEmpty) return null;
    return SingboxPremium(
      uuid: uuid,
      hy2Password: pwd ?? '',
      hysteria2: Hysteria2Params.fromJson(j['hysteria2'] as Map<String, dynamic>?),
      reality:   RealityParams.fromJson(j['reality']     as Map<String, dynamic>?),
      ws:        WsParams.fromJson(j['ws']               as Map<String, dynamic>?),
    );
  }

  /// 至少有一层可用，才谈得上用 sing-box 连这个节点。
  bool get usable => hysteria2 != null || reality != null || ws != null;
}

/// 快速层：Hysteria2(QUIC)。端口跳跃由 sing-box 原生完成，客户端只是透传范围。
class Hysteria2Params {
  final String  server;
  final int     port;        // 服务端实际监听端口
  final String? ports;       // 可空；跳跃范围，如 "30000-49999"
  final String? obfsPassword;

  const Hysteria2Params({required this.server, required this.port, this.ports, this.obfsPassword});

  static Hysteria2Params? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final server = j['server'] as String?;
    final port   = (j['port'] as num?)?.toInt();
    if (server == null || server.isEmpty || port == null) return null;
    return Hysteria2Params(
      server: server,
      port: port,
      ports: (j['ports'] as String?)?.trim().isEmpty ?? true ? null : (j['ports'] as String).trim(),
      obfsPassword: j['obfs_password'] as String?,
    );
  }

  Map<String, dynamic> outbound(String password) => {
    'type': 'hysteria2',
    'server': server,
    'server_port': port,
    if (ports != null) 'server_ports': [ports],
    'password': password,
    if (obfsPassword != null && obfsPassword!.isNotEmpty)
      'obfs': {'type': 'salamander', 'password': obfsPassword},
    'tls': {'enabled': true, 'server_name': server, 'insecure': true},
  };
}

/// 强力层：VLESS + Reality（偷大站 TLS 握手，无需证书）。必须直连节点，不能经 CF。
class RealityParams {
  final String  server;
  final int     port;
  final String  publicKey;
  final String  shortId;
  final String  sni;
  final String? flow;

  const RealityParams({
    required this.server, required this.port,
    required this.publicKey, required this.shortId, required this.sni, this.flow,
  });

  static RealityParams? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final server = j['server'] as String?;
    final port   = (j['port'] as num?)?.toInt();
    final pbk    = j['public_key'] as String?;
    final sni    = j['sni'] as String?;
    // Reality 少任何一个参数都握不了手，宁可当作该层不可用。
    if (server == null || port == null || pbk == null || sni == null) return null;
    return RealityParams(
      server: server, port: port, publicKey: pbk,
      shortId: j['short_id'] as String? ?? '',
      sni: sni,
      flow: (j['flow'] as String?)?.trim().isEmpty ?? true ? null : (j['flow'] as String).trim(),
    );
  }

  Map<String, dynamic> outbound(String uuid) => {
    'type': 'vless',
    'server': server,
    'server_port': port,
    'uuid': uuid,
    if (flow != null) 'flow': flow,
    'tls': {
      'enabled': true,
      'server_name': sni,
      'utls': {'enabled': true, 'fingerprint': 'chrome'},
      'reality': {
        'enabled': true,
        'public_key': publicKey,
        if (shortId.isNotEmpty) 'short_id': shortId,
      },
    },
  };
}

/// 超级层：VLESS + WS + TLS，经 Cloudflare。阶段 2 才会下发。
class WsParams {
  final String host;   // CF 域名，同时用作 TLS SNI 与 Host 头
  final int    port;
  final String path;

  const WsParams({required this.host, required this.port, required this.path});

  static WsParams? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final host = j['host'] as String?;
    final path = j['path'] as String?;
    if (host == null || host.isEmpty || path == null || path.isEmpty) return null;
    return WsParams(host: host, port: (j['port'] as num?)?.toInt() ?? 443, path: path);
  }

  Map<String, dynamic> outbound(String uuid) => {
    'type': 'vless',
    'server': host,
    'server_port': port,
    'uuid': uuid,
    'tls': {'enabled': true, 'server_name': host},
    'transport': {'type': 'ws', 'path': path, 'headers': {'Host': host}},
  };
}
