import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// 把随包的 sing-box 规则集(assets/routes/airlane-cn.srs)释放到可写目录，返回其绝对路径，
/// 供 sing-box 本地 rule_set 引用。
///
/// 为什么要释放：Flutter 的 asset 不是真实文件路径，而 sing-box 的 `rule_set: {type:local}`
/// 需要一个磁盘路径。Android 的 :singbox 进程与主进程同 UID，可读主进程写进
/// getApplicationSupportDirectory() 的文件；Windows 的 sing-box.exe 子进程同理。
/// Apple 不用这里 —— 扩展把 .srs 打进 bundle，配置里用占位符 `$RULESET_DIR/airlane-cn.srs`。
class RuleSetAssets {
  RuleSetAssets._();

  static const String _asset = 'assets/routes/airlane-cn.srs';
  static String? _cachedPath;

  /// 返回 airlane-cn.srs 的本地绝对路径；释放失败返回 null（调用方回退到 cn_cidr ip_cidr）。
  static Future<String?> cnRuleSetPath() async {
    if (_cachedPath != null) return _cachedPath;
    try {
      final data  = await rootBundle.load(_asset);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final dir   = await getApplicationSupportDirectory();
      final f     = File('${dir.path}/airlane-cn.srs');
      // 已存在且字节数一致则不重写（发版换了规则集时字节数变化会触发覆盖）。
      if (!await f.exists() || (await f.length()) != bytes.length) {
        await f.writeAsBytes(bytes, flush: true);
      }
      _cachedPath = f.path;
      return _cachedPath;
    } catch (_) {
      return null;
    }
  }
}
