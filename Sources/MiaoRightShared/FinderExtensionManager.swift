import Foundation

/// 本机所有 Finder Sync 扩展的信息与启用/禁用管理。
/// 底层调用 `pluginkit` 命令行工具。
public struct FinderExtensionInfo: Identifiable, Sendable {
    public let bundleID: String
    public let name: String
    public let path: String
    public var isEnabled: Bool
    public var id: String { bundleID }
    /// 是否为妙右自身的扩展(不允许从界面禁用)
    public var isSelf: Bool { bundleID == "com.miaoright.app.FinderSync" }
}

public enum FinderExtensionManager {
    /// 列出本机所有 Finder Sync 扩展及其启用状态
    public static func list() -> [FinderExtensionInfo] {
        parseList(run("/usr/bin/pluginkit", ["-m", "-v", "-p", "com.apple.FinderSync"]).output)
    }

    static func parseList(_ output: String) -> [FinderExtensionInfo] {
        var result: [FinderExtensionInfo] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains(".appex") else { continue }
            let enabled = trimmed.hasPrefix("+")
            // 第一列含状态符号和 bundleID(version)，第二列是 UUID。
            let parts = trimmed.split(separator: "\t", omittingEmptySubsequences: true)
            guard parts.count >= 4 else { continue }
            guard let bundleToken = parts[0].split(whereSeparator: \.isWhitespace).last else { continue }
            let bundlePart = String(bundleToken)
            let bundleID = bundlePart.components(separatedBy: "(").first ?? bundlePart
            let path = String(parts[3]).trimmingCharacters(in: .whitespaces)
            let name = displayName(fromPath: path)
            result.append(FinderExtensionInfo(bundleID: String(bundleID), name: name, path: path, isEnabled: enabled))
        }
        return result.sorted { lhs, rhs in
            if lhs.isSelf != rhs.isSelf { return lhs.isSelf }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// 启用/禁用某个扩展
    @discardableResult
    public static func setEnabled(bundleID: String, enabled: Bool) -> Bool {
        let election = enabled ? "use" : "ignore"
        return run("/usr/bin/pluginkit", ["-e", election, "-i", bundleID]).succeeded
    }

    /// 重新从 pluginkit 读取最新状态
    public static func refreshRegistration() {
        // pluginkit 内部状态在 -e 后需要一点时间生效,但命令本身是同步的
    }

    /// 从 .appex 路径读取显示名
    private static func displayName(fromPath path: String) -> String {
        let bundle = Bundle(path: path)
        let name = bundle?.infoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle?.infoDictionary?["CFBundleName"] as? String
        if let name, !name.isEmpty { return name }
        return (path as NSString).lastPathComponent
    }

    private static func run(_ launchPath: String, _ arguments: [String]) -> (output: String, succeeded: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (String(data: data, encoding: .utf8) ?? "", process.terminationStatus == 0)
        } catch {
            return ("", false)
        }
    }
}
