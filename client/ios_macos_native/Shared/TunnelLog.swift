import Foundation

/// 隧道扩展的共享日志。
///
/// 扩展跑在独立进程里，TestFlight / 正式包又看不到控制台，出问题时基本是黑盒。
/// 这里把关键生命周期写进 App Group 容器的文件，主 App 可以直接读出来展示
/// （见「我的 → 错误信息」），无需数据线、无需 Xcode。
///
/// 只保留最近 [maxLines] 行，避免无限增长。
enum TunnelLog {
    /// 每个扩展一个文件：awg.log / singbox.log
    static var name = "tunnel"
    private static let maxLines = 120
    private static let queue = DispatchQueue(label: "com.mirrorspeed.tunnellog")

    /// App Group 容器：扩展 bundle id 去掉最后一段就是主 App 的 id。
    static var groupId: String {
        let bundle = Bundle.main.bundleIdentifier ?? "com.mirrorspeed.mirrorspeedVpn.X"
        return "group." + bundle.components(separatedBy: ".").dropLast().joined(separator: ".")
    }

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupId)?
            .appendingPathComponent("\(name).log")
    }

    static func log(_ message: String) {
        queue.async {
            guard let url = fileURL else { return }
            let ts = ISO8601DateFormatter().string(from: Date()).suffix(14).prefix(8)
            let line = "[\(ts)] \(message)\n"
            var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
                .components(separatedBy: "\n")
            lines.append(line.trimmingCharacters(in: .newlines))
            if lines.count > maxLines { lines = Array(lines.suffix(maxLines)) }
            try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// 主 App 侧读取（插件用）。
    static func read(groupId: String, name: String) -> String? {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupId)?
            .appendingPathComponent("\(name).log") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
