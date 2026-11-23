import AppKit
import Foundation

public enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    public var displayName: String {
        switch self {
        case .system: L10n.text("跟随系统", "Follow System")
        case .light: L10n.text("浅色", "Light")
        case .dark: L10n.text("深色", "Dark")
        }
    }

    public var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

public enum AppearanceManager {
    private static let storageKey = "appAppearance"
    public static var current: AppearanceMode {
        get { AppearanceMode(rawValue: AppGroup.standardDefaults.string(forKey: storageKey) ?? "") ?? .system }
        set { AppGroup.standardDefaults.set(newValue.rawValue, forKey: storageKey); apply() }
    }
    public static func apply() {
        NSApp.appearance = current.nsAppearance
    }
}
