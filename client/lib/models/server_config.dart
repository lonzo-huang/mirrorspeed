class ServerConfig {
  final String  id;
  final String  displayName;
  final String  flagEmoji;
  final String  location;
  final String  endpoint;
  final int     port;
  final String  wgConf;
  /// HMAC-SHA256 secret used for server-side port hopping.
  /// Present when the server is configured with 05-port-hopping.sh.
  /// Null means port hopping is disabled for this server (use [port] directly).
  final String? portSecret;
  int?          latencyMs; // 运行时测量

  ServerConfig({
    required this.id,
    required this.displayName,
    required this.flagEmoji,
    required this.location,
    required this.endpoint,
    required this.port,
    required this.wgConf,
    this.portSecret,
    this.latencyMs,
  });

  factory ServerConfig.fromJson(Map<String, dynamic> j) => ServerConfig(
    id:          j['id']           as String,
    displayName: j['display_name'] as String,
    flagEmoji:   j['flag_emoji']   as String? ?? '',
    location:    j['location']     as String? ?? '',
    endpoint:    j['endpoint']     as String,
    port:        j['port']         as int,
    wgConf:      j['wg_conf']      as String,
    portSecret:  j['port_secret']  as String?,
  );

  String get label => '$flagEmoji $displayName';
}

class DeviceInfo {
  final String             id;
  final String             label;
  final List<ServerConfig> servers;
  final int?               dailyQuotaBytes; // null = 无限制（付费用户）
  final int                dailyBytesUsed;
  final bool               isSuspended;

  DeviceInfo({
    required this.id,
    required this.label,
    required this.servers,
    this.dailyQuotaBytes,
    this.dailyBytesUsed = 0,
    this.isSuspended    = false,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> j) => DeviceInfo(
    id:               j['id']    as String,
    label:            j['label'] as String,
    dailyQuotaBytes:  j['daily_quota_bytes'] as int?,
    dailyBytesUsed:   (j['daily_bytes_used'] as num?)?.toInt() ?? 0,
    isSuspended:      j['is_suspended'] as bool? ?? false,
    servers: (j['servers'] as List)
        .map((s) => ServerConfig.fromJson(s as Map<String, dynamic>))
        .toList(),
  );

  /// 剩余免费流量（null = 不限量）
  int? get dailyBytesRemaining =>
      dailyQuotaBytes == null ? null : (dailyQuotaBytes! - dailyBytesUsed).clamp(0, dailyQuotaBytes!);

  /// 已使用比例 0.0~1.0（null = 不限量）
  double? get usageRatio => dailyQuotaBytes == null
      ? null
      : (dailyBytesUsed / dailyQuotaBytes!).clamp(0.0, 1.0);
}
