class ServerConfig {
  final String id;
  final String displayName;
  final String flagEmoji;
  final String location;
  final String endpoint;
  final int    port;
  final String wgConf;
  int?         latencyMs; // 运行时测量

  ServerConfig({
    required this.id,
    required this.displayName,
    required this.flagEmoji,
    required this.location,
    required this.endpoint,
    required this.port,
    required this.wgConf,
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
  );

  String get label => '$flagEmoji $displayName';
}

class DeviceInfo {
  final String        id;
  final String        label;
  final List<ServerConfig> servers;

  DeviceInfo({ required this.id, required this.label, required this.servers });

  factory DeviceInfo.fromJson(Map<String, dynamic> j) => DeviceInfo(
    id:      j['id']    as String,
    label:   j['label'] as String,
    servers: (j['servers'] as List)
        .map((s) => ServerConfig.fromJson(s as Map<String, dynamic>))
        .toList(),
  );
}
