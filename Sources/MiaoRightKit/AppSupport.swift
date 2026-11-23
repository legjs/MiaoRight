import SwiftUI
import MiaoRightShared

/// 跨窗口/跨进程打开主窗口与设置页的支撑类型。
/// (原属主 App 入口文件,二次开发时移入 Kit 供 SettingsView/MenuBarController 使用)

extension Notification.Name {
    public static let openSettings = Notification.Name("openSettings")
    public static let openSettingsTab = Notification.Name("openSettingsTab")
    public static let openMainWindow = Notification.Name("openMainWindow")
    public static let importScriptsRequested = Notification.Name("importScriptsRequested")
    public static let exportAllScriptsRequested = Notification.Name("exportAllScriptsRequested")
}

@MainActor
public final class SettingsActionStorage {
    public static let shared = SettingsActionStorage()
    var openSettings: (() -> Void)?
    public func capture(_ action: OpenSettingsAction) {
        openSettings = {
            action()
        }
    }

    public func showSettings() {
        if let openSettings {
            openSettings()
        } else {
            NotificationCenter.default.post(name: .openSettings, object: nil)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
public final class WindowActionStorage {
    public static let shared = WindowActionStorage()
    public var openWindow: ((String) -> Void)?
    weak var mainWindow: NSWindow?

    public func capture(_ action: OpenWindowAction) {
        openWindow = { id in
            action(id: id)
        }
    }

    public func captureMainWindow(_ window: NSWindow?) {
        guard let window, window.canBecomeMain, !window.isSheet else { return }
        mainWindow = window
    }

    /// 应用级 openWindow(AppCommands 菜单桥注入,与主窗口生死无关)
    public var commandsOpenWindow: ((String) -> Void)?

    public func showMainWindow() {
        guard !AppGroup.isIsolated else { return }
        let window = mainWindow ?? NSApp.windows.first(where: {
            $0.canBecomeMain &&
                $0.contentView != nil &&
                ($0.identifier?.rawValue.contains("main") == true || !$0.title.isEmpty)
        })

        if let window {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            mainWindow = window
        } else {
            // 窗口从未创建/已销毁:优先 SwiftUI openWindow(需窗口内容捕获过),
            // 最终兜底走应用级命令桥 —— 窗口零存在也能开出主窗口
            if let openWindow {
                openWindow("main")
            } else {
                commandsOpenWindow?("main")
            }
            // 确定性兜底:0.3s 后仍无主窗口,直接创建 NSWindow 承载主界面
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let exists = NSApp.windows.contains {
                    $0.identifier?.rawValue.contains("main") == true && $0.isVisible
                }
                if !exists {
                    NotificationCenter.default.post(
                        name: Notification.Name("com.miaoright.openMainWindowFallback"), object: nil
                    )
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
