class ServerConfig {
  final String  id;
  final String  displayName;
  final String  flagEmoji;
  final String  location;
  final String  endpoint;
  /// Hostname for wstunnel TLS relay connections.
  /// Always a domain name (never a raw IP), derived from the server's api_url
  /// by the portal. Falls back to [endpoint] if the portal doesn't provide it.
  final String  relayHost;
  final int     port;
  final String  wgConf;
  /// HMAC-SHA256 secret used for server-side port hopping.
  /// Null means port hopping is disabled for this server (use [port] directly).
  final String? portSecret;
  /// Cloudflare Tunnel WebSocket base URL, e.g. "wss://xxx.cfargotunnel.com".
  /// Used as tertiary relay if wstunnel on 443 fails.
  /// Null means Cloudflare relay is not configured for this server.
  final String? cfRelayUrl;

  // ── 负载信息（来自 portal，每分钟刷新）────────────────────────
  /// 当前活跃隧道数。
  int           activePeers;
  /// 容量上限（peer 数）。
  int           maxPeers;
  /// 负载百分比 0–100。
  int           loadPercent;
  /// online / degraded / offline。
  String        status;

  // ── 延迟：10 秒滚动平均 ───────────────────────────────────────
  // 每次 ping 把样本(毫秒,时间戳)压入；读取时丢弃 10 秒前的样本再求平均。
  final List<int> _latMs = [];
  final List<int> _latAt = [];

  /// 当前的 10 秒滚动平均延迟（毫秒）；无有效样本时为 null。
  int? latencyMs;

  /// 记录一次 ping 结果。[ms] 为 null 表示本次失败（仅清理过期样本，不计入）。
  void addLatencySample(int? ms) {
    final now = DateTime.now().millisecondsSinceEpoch;
    while (_latAt.isNotEmpty && now - _latAt.first > 10000) {
      _latAt.removeAt(0);
      _latMs.removeAt(0);
    }
    if (ms != null) { _latMs.add(ms); _latAt.add(now); }
    if (_latMs.isEmpty) { latencyMs = null; return; }
    latencyMs = (_latMs.reduce((a, b) => a + b) / _latMs.length).round();
  }

  ServerConfig({
    required this.id,
    required this.displayName,
    required this.flagEmoji,
    required this.location,
    required this.endpoint,
    String?  relayHost,
    required this.port,
    required this.wgConf,
    this.portSecret,
    this.cfRelayUrl,
    int? latencyMs,
    this.activePeers = 0,
    this.maxPeers    = 0,
    this.loadPercent = 0,
    this.status      = 'online',
  }) : relayHost = relayHost ?? endpoint,
       latencyMs = latencyMs;

  factory ServerConfig.fromJson(Map<String, dynamic> j) => ServerConfig(
    id:          j['id']           as String,
    displayName: j['display_name'] as String,
    flagEmoji:   j['flag_emoji']   as String? ?? '',
    location:    j['location']     as String? ?? '',
    endpoint:    j['endpoint']     as String,
    relayHost:   j['relay_host']   as String?,  // null → falls back to endpoint
    port:        j['port']         as int,
    wgConf:      j['wg_conf']      as String,
    portSecret:  j['port_secret']  as String?,
    cfRelayUrl:  j['cf_relay_url'] as String?,
    activePeers: (j['active_peers'] as num?)?.toInt() ?? 0,
    maxPeers:    (j['max_peers']    as num?)?.toInt() ?? 0,
    loadPercent: (j['load_percent'] as num?)?.toInt() ?? 0,
    status:      j['status'] as String? ?? 'online',
  );

  // ── 负载分档（三档色块）────────────────────────────────────────
  /// 0=空闲(<50%) · 1=适中(50–85%) · 2=繁忙(>85%)；offline 视为繁忙。
  int get loadTier {
    if (status == 'offline') return 2;
    if (loadPercent > 85) return 2;
    if (loadPercent >= 50) return 1;
    return 0;
  }

  /// 公开节点（/api/servers）——仅用于未登录时展示列表，无 wg_conf/密钥。
  /// 连接前必须登录拉取真实配置。
  factory ServerConfig.fromPublicJson(Map<String, dynamic> j) => ServerConfig(
    id:          (j['id'] ?? '').toString(),
    displayName: (j['display_name'] ?? j['name'] ?? '') as String,
    flagEmoji:   j['flag_emoji'] as String? ?? '',
    location:    j['location']   as String? ?? '',
    endpoint:    (j['endpoint'] ?? '') as String,
    port:        (j['port'] as num?)?.toInt() ?? 51820,
    wgConf:      '',          // 占位：未登录无配置
    latencyMs:   (j['latency_ms'] as num?)?.toInt(),
  );

  /// 是否为「仅展示」的公开节点（无可用配置，连接前需登录）。
  bool get isDisplayOnly => wgConf.isEmpty;

  String get label => '$flagEmoji $displayName';
}

// display_name 在 DB 里通常是中文（如「德国 法兰克福 01」）。非中文设备改用
// 英文的 location（如 Frankfurt）；location 为空时回退 display_name。
extension ServerConfigName on ServerConfig {
  String displayLabel(bool isZh) =>
      isZh ? displayName : (location.isNotEmpty ? location : displayName);
}

class DeviceInfo {
  final String             id;
  final String             label;
  final List<ServerConfig> servers;
  final int?               dailyQuotaBytes;   // null = unlimited (paid users)
  final int?               dailyQuotaSeconds; // 时间试用上限（秒）；null = 无限
  final int                dailyBytesUsed;
  final bool               isSuspended;

  DeviceInfo({
    required this.id,
    required this.label,
    required this.servers,
    this.dailyQuotaBytes,
    this.dailyQuotaSeconds,
    this.dailyBytesUsed = 0,
    this.isSuspended    = false,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> j) => DeviceInfo(
    id:                j['id']    as String,
    label:             j['label'] as String,
    dailyQuotaBytes:   j['daily_quota_bytes']   as int?,
    dailyQuotaSeconds: (j['daily_quota_seconds'] as num?)?.toInt(),
    dailyBytesUsed:    (j['daily_bytes_used'] as num?)?.toInt() ?? 0,
    isSuspended:       j['is_suspended'] as bool? ?? false,
    servers: (j['servers'] as List)
        .map((s) => ServerConfig.fromJson(s as Map<String, dynamic>))
        .toList(),
  );

  /// Remaining free quota (null = unlimited)
  int? get dailyBytesRemaining =>
      dailyQuotaBytes == null ? null : (dailyQuotaBytes! - dailyBytesUsed).clamp(0, dailyQuotaBytes!);

  /// Usage ratio 0.0–1.0 (null = unlimited)
  double? get usageRatio => dailyQuotaBytes == null
      ? null
      : (dailyBytesUsed / dailyQuotaBytes!).clamp(0.0, 1.0);
}
