import Foundation

/// 加密保险箱配置。只记录镜像位置与启用标记,密码永不落盘;
/// 主 App 写入,Finder 扩展经 App Group 读取以判断菜单可用性。
public struct VaultConfig: Equatable, Sendable {
    public static let actionName = "加入保险箱"
    public static let defaultVolumeName = "保险箱"

    public let bundlePath: String
    public init(bundlePath: String) { self.bundlePath = bundlePath }

    public var bundleURL: URL { URL(fileURLWithPath: bundlePath, isDirectory: true) }

    public var bundleExists: Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: bundlePath, isDirectory: &isDirectory) else { return false }
        return isDirectory.boolValue
    }

    // MARK: - App Group 持久化

    private static let configuredKey = "vault.configured"
    private static let pathKey = "vault.path"

    public static var current: VaultConfig? {
        guard let defaults = AppGroup.userDefaults, defaults.bool(forKey: configuredKey),
              let path = defaults.string(forKey: pathKey), path.hasPrefix("/") else { return nil }
        return VaultConfig(bundlePath: path)
    }

    public static func save(_ config: VaultConfig) {
        guard let defaults = AppGroup.userDefaults else { return }
        defaults.set(true, forKey: configuredKey)
        defaults.set(config.bundlePath, forKey: pathKey)
    }

    public static func clear() {
        guard let defaults = AppGroup.userDefaults else { return }
        defaults.removeObject(forKey: configuredKey)
        defaults.removeObject(forKey: pathKey)
    }

    /// 菜单可用性只看配置标记;镜像被外部删除的细节在主 App 执行时再处理,
    /// 扩展沙箱无法探测自定义位置,不能据此隐藏入口。
    public static var isAvailable: Bool { current != nil }
}
