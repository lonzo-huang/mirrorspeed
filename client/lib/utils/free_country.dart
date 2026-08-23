// 共享节点名解析：新版格式「英文国家名 - IP」（如 "South Korea - 1.2.3.4"），
// 兼容旧版旗帜 emoji。供服务器列表与主页统一使用，避免各处重复。

// 分组 key：英文国家名 / ISO 码（旗帜）/ ''。
String freeCountryKey(String name) {
  final idx = name.indexOf(' - ');
  if (idx > 0) {
    final c = name.substring(0, idx).trim();
    if (c.isNotEmpty) return c;
  }
  return _isoFromFlag(name);
}

String _isoFromFlag(String name) {
  final runes = name.runes.toList();
  const base = 0x1F1E6;
  for (var i = 0; i < runes.length - 1; i++) {
    final a = runes[i] - base, b = runes[i + 1] - base;
    if (a >= 0 && a <= 25 && b >= 0 && b <= 25) {
      return String.fromCharCode(65 + a) + String.fromCharCode(65 + b);
    }
  }
  return '';
}

String freeFlagOf(String iso) {
  if (iso.length != 2) return '';
  const base = 0x1F1E6;
  return String.fromCharCodes([base + (iso.codeUnitAt(0) - 65), base + (iso.codeUnitAt(1) - 65)]);
}

// 分组/国家的本地化显示名（key 可能是英文国家名或 ISO 码）。
String freeCountryLabel(String key, bool zh) {
  if (key.isEmpty) return zh ? '其他' : 'Other';
  final byName = _kByName[key];
  if (byName != null) return zh ? byName[0] : key;
  final byIso = _kByIso[key];
  if (byIso != null) return zh ? byIso[0] : byIso[1];
  return key;
}

String freeCountryFlag(String key) {
  final byName = _kByName[key];
  if (byName != null) return freeFlagOf(byName[1]);
  if (key.length == 2) return freeFlagOf(key);
  return '';
}

// 单条线路名：「Country - IP」→ IP（带 -1/-2 后缀原样保留）；否则清理后的名。
String freeLineName(String name, String server) {
  final idx = name.indexOf(' - ');
  if (idx > 0) {
    final rest = name.substring(idx + 3).trim();
    return rest.isEmpty ? server : rest;
  }
  var s = name.replaceAll(RegExp(r'[\u{1F1E6}-\u{1F1FF}]', unicode: true), '');
  s = s.replaceAll(RegExp(r'\d+(\.\d+)?\s*[KMG]B/s'), '');
  s = s.split('|').first.split('·').first.trim();
  s = s.replaceAll(RegExp(r'^\W+'), '').trim();
  if (s.length > 26) s = '${s.substring(0, 26)}…';
  return s.isEmpty ? server : s;
}

// ISO → [中文名, 英文名]
const Map<String, List<String>> _kByIso = {
  'HK': ['香港', 'Hong Kong'], 'TW': ['台湾', 'Taiwan'], 'JP': ['日本', 'Japan'],
  'KR': ['韩国', 'South Korea'], 'SG': ['新加坡', 'Singapore'], 'US': ['美国', 'United States'],
  'CA': ['加拿大', 'Canada'], 'GB': ['英国', 'United Kingdom'], 'DE': ['德国', 'Germany'],
  'FR': ['法国', 'France'], 'NL': ['荷兰', 'Netherlands'], 'RU': ['俄罗斯', 'Russia'],
  'IN': ['印度', 'India'], 'AU': ['澳大利亚', 'Australia'], 'BR': ['巴西', 'Brazil'],
  'IT': ['意大利', 'Italy'], 'ES': ['西班牙', 'Spain'], 'SE': ['瑞典', 'Sweden'],
  'CH': ['瑞士', 'Switzerland'], 'PL': ['波兰', 'Poland'], 'FI': ['芬兰', 'Finland'],
  'NO': ['挪威', 'Norway'], 'IE': ['爱尔兰', 'Ireland'], 'AT': ['奥地利', 'Austria'],
  'TR': ['土耳其', 'Turkey'], 'UA': ['乌克兰', 'Ukraine'], 'CZ': ['捷克', 'Czechia'],
  'RO': ['罗马尼亚', 'Romania'], 'VN': ['越南', 'Vietnam'], 'TH': ['泰国', 'Thailand'],
  'MY': ['马来西亚', 'Malaysia'], 'ID': ['印尼', 'Indonesia'], 'PH': ['菲律宾', 'Philippines'],
  'AE': ['阿联酋', 'UAE'], 'IL': ['以色列', 'Israel'], 'ZA': ['南非', 'South Africa'],
  'MX': ['墨西哥', 'Mexico'], 'AR': ['阿根廷', 'Argentina'], 'CL': ['智利', 'Chile'],
  'KZ': ['哈萨克斯坦', 'Kazakhstan'], 'CO': ['哥伦比亚', 'Colombia'], 'CN': ['中国', 'China'],
  'MO': ['澳门', 'Macau'], 'PT': ['葡萄牙', 'Portugal'], 'GR': ['希腊', 'Greece'],
  'HU': ['匈牙利', 'Hungary'], 'BE': ['比利时', 'Belgium'], 'DK': ['丹麦', 'Denmark'],
};

// 英文国家名 → [中文名, ISO]（由 _kByIso 反转）。
final Map<String, List<String>> _kByName = {
  for (final e in _kByIso.entries) e.value[1]: [e.value[0], e.key],
};
