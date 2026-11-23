import Foundation

/// 应用语言:跟随系统 / 简体中文 / English。
/// 存储在 App Group 默认域,主 App 与 Finder 扩展共用同一设置。
public enum AppLanguage: String, CaseIterable {
    case system
    case zhHans = "zh-Hans"
    case english = "en"

    public var displayName: String {
        switch self {
        case .system: L10n.text("跟随系统", "Follow System")
        case .zhHans: "简体中文"
        case .english: "English"
        }
    }
}

public enum L10n {
    public static let languageChangedNotification = Notification.Name("com.miaoright.languageChanged")
    public static let storageKey = "appLanguage"

    /// 当前生效语言(每次实时读取,切换立即生效)
    public static var language: AppLanguage {
        let stored = AppGroup.userDefaults?.string(forKey: storageKey) ?? AppLanguage.system.rawValue
        let setting = AppLanguage(rawValue: stored) ?? .system
        if setting == .system {
            let preferred = Locale.preferredLanguages.first ?? "zh-Hans"
            return preferred.hasPrefix("zh") ? .zhHans : .english
        }
        return setting
    }

    public static var isEnglish: Bool {
        language == .english
    }

    /// 取文案:中文在前,英文在后
    public static func text(_ zh: String, _ en: String) -> String {
        isEnglish ? en : zh
    }

    public static func setLanguage(_ language: AppLanguage) {
        AppGroup.userDefaults?.set(language.rawValue, forKey: storageKey)
        // 系统级菜单(文件/编辑/窗口/帮助)跟随 App 的本地化资源,
        // 通过 AppleLanguages 让系统菜单在重启后也保持一致
        switch language {
        case .system:
            AppGroup.standardDefaults.removeObject(forKey: "AppleLanguages")
        case .zhHans:
            AppGroup.standardDefaults.set(["zh-Hans"], forKey: "AppleLanguages")
        case .english:
            AppGroup.standardDefaults.set(["en"], forKey: "AppleLanguages")
        }
        // 进程内通知:设置页/主窗口立即刷新
        NotificationCenter.default.post(name: L10n.languageChangedNotification, object: nil)
        guard !AppGroup.isIsolated else { return }
        // 跨进程通知:Finder 扩展在下次构建菜单时读取新语言
        DistributedNotificationCenter.default().postNotificationName(
            L10n.languageChangedNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
