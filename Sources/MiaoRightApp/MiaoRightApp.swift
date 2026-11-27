import MiaoRightKit
import MiaoRightShared
import SwiftUI


private enum CrossProcessNotifications {
    static let openMainWindow = NSNotification.Name("com.miaoright.openMainWindow")
}

@MainActor
class MiaoRightAppDelegate: NSObject, NSApplicationDelegate {
    private var launchWindowDeadline = Date()

    func applicationWillFinishLaunching(_: Notification) {
        WindowActionStorage.shared.suppressAutomaticMainWindow = true
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(mainWindowDidBecomeVisible(_:)), name: name, object: nil)
        }
        launchWindowDeadline = Date().addingTimeInterval(1.2)
        let timer = Timer(timeInterval: 0.02, target: self, selector: #selector(hideLaunchWindowTick(_:)), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func mainWindowDidBecomeVisible(_ notification: Notification) {
        guard WindowActionStorage.shared.suppressAutomaticMainWindow,
              let window = notification.object as? NSWindow,
              window.identifier?.rawValue.hasPrefix("main-AppWindow") == true else { return }
        window.orderOut(nil)
    }

    @objc private func hideLaunchWindowTick(_ timer: Timer) {
        guard WindowActionStorage.shared.suppressAutomaticMainWindow, Date() < launchWindowDeadline else {
            timer.invalidate()
            return
        }
        for window in NSApp.windows where window.identifier?.rawValue.hasPrefix("main-AppWindow") == true && window.isVisible {
            window.orderOut(nil)
        }
    }

    func applicationDidFinishLaunching(_: Notification) {
        AppearanceManager.apply()
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }

        // 强杀/崩溃后,保存的窗口恢复状态可能是「一批不可见窗口」,而本应用
        // 无常驻 Dock 图标,没有入口能把它们调出来 → 每次启动清掉恢复数据,
        // 并把主窗口强制调到前台(落在主屏之外时先挪回主屏)
        let savedStateDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Saved Application State/com.miaoright.app.savedState", isDirectory: true)
        try? FileManager.default.removeItem(at: savedStateDir)
        let mainDisplayBounds = CGDisplayBounds(CGMainDisplayID())
        for w in NSApp.windows where w.identifier?.rawValue.hasPrefix("main-AppWindow") == true {
            var frame = w.frame
            if !mainDisplayBounds.intersects(frame) {
                frame.origin.x = mainDisplayBounds.midX - frame.width / 2
                frame.origin.y = mainDisplayBounds.midY - frame.height / 2
                w.setFrame(frame, display: true)
            }
            if w.isVisible {
                w.orderOut(nil)
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: CrossProcessNotifications.openMainWindow,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                WindowActionStorage.shared.showMainWindow()
            }
        }

        // 零窗口兜底:showMainWindow 走投无路时直接建窗
        NotificationCenter.default.addObserver(
            forName: Notification.Name("com.miaoright.openMainWindowFallback"),
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                MiaoRightApp.presentFallbackMainWindow()
            }
        }

        // Present a result window when an action with the "Show result" output
        // mode finishes (shared pipeline with the script editor's test run).
        NotificationCenter.default.addObserver(
            forName: ScriptExecutor.showResultNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let result = notification.userInfo?["result"] as? ScriptExecutionResult else { return }
            Task { @MainActor in
                ResultWindowPresenter.shared.present(result)
            }
        }
    }

    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: L10n.text("打开妙右", "Open MiaoRight"),
            action: #selector(openMainWindow),
            keyEquivalent: ""
        ))
        menu.items.last?.target = self
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: L10n.text("设置…", "Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ""
        ))
        menu.items.last?.target = self
        menu.addItem(NSMenuItem(
            title: L10n.text("重启 Finder", "Restart Finder"),
            action: #selector(restartFinder),
            keyEquivalent: ""
        ))
        menu.items.last?.target = self
        menu.addItem(NSMenuItem(
            title: L10n.text("显示/隐藏 Dock 图标", "Toggle Dock Icon"),
            action: #selector(toggleDockIcon),
            keyEquivalent: ""
        ))
        menu.items.last?.target = self
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: L10n.text("退出妙右", "Quit MiaoRight"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        ))
        menu.items.last?.target = self
        return menu
    }

    @MainActor @objc private func openMainWindow() {
        WindowActionStorage.shared.showMainWindow()
    }

    @MainActor @objc private func openSettings() {
        SettingsActionStorage.shared.showSettings()
    }

    @MainActor @objc private func restartFinder() {
        FinderControl.restartFinder()
    }

    @MainActor @objc private func toggleDockIcon() {
        let newValue = !AppPreferences.showDockIcon
        let state = AppVisibilityCoordinator.setDockIconVisible(newValue)
        if state.showDockIcon {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @MainActor @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            WindowActionStorage.shared.showMainWindow()
        }
        return true
    }
}

@main
struct MiaoRightApp: App {
    @NSApplicationDelegateAdaptor(MiaoRightAppDelegate.self) private var appDelegate
    @State private var scriptStore = ScriptStore.shared
    @State private var monitoredFolderService = MonitoredFolderService.shared

    init() {
        // 启动时把 App 内语言选择同步到系统本地化(菜单栏等,重启后保持一致)
        if let stored = AppGroup.userDefaults?.string(forKey: L10n.storageKey),
           let mode = AppLanguage(rawValue: stored), mode != .system {
            AppGroup.standardDefaults.set(mode == .english ? ["en"] : ["zh-Hans"], forKey: "AppleLanguages")
        }
        AppPreferences.registerDefaults()
        MonitoredFolders.seedInitialDefaultFoldersIfNeeded()

        // Menu bar icon + Dock visibility
        DispatchQueue.main.async {
            Task { @MainActor in
                AppVisibilityCoordinator.applyInitialVisibility()
            }
        }

        // Initialize ScriptExecutor to register notification listener for extension requests
        _ = ScriptExecutor.shared
        Task { @MainActor in
            ScriptStore.shared.loadIfNeeded()
            // 剪贴板历史:启动即监听;注册全局呼出热键(默认 ⇧⌘V)
            ClipboardHistoryService.shared.startMonitoring()
            HotkeyCenter.shared.registerDefault()
            // 旧工作流一次性迁移为组合菜单(workflows.json 改名锚点保证幂等)
            WorkflowMigrator.migrateIfNeeded(store: ScriptStore.shared)
            await AppUpdateService.shared.checkIfDue()
        }
        if ProcessInfo.processInfo.arguments.contains("--miaoright-execution-requested") {
            ScriptExecutor.shared.processPendingExecutionAfterLaunchRequest()
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            mainWindowContent
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 780, height: 600)
        .commands {
            AppCommands()
        }
    }

    private var mainWindowContent: some View {
        Self.makeMainWindowContent()
    }

    /// 主窗口内容装配(WindowGroup 与零窗口兜底共用)
    @MainActor
    static func makeMainWindowContent() -> some View {
        ContentView()
            .environment(ScriptStore.shared)
            .environment(MonitoredFolderService.shared)
            .modifier(WindowActionCapture())
            .background(MainWindowCaptureView())
            .onAppear {
                Task { @MainActor in
                    ScriptStore.shared.loadIfNeeded()
                }
            }
    }

    /// 零窗口兜底:WindowGroup 主窗不存在时,直接创建 NSWindow 承载同一套界面。
    /// identifier 仍含 "main",showMainWindow 的查找逻辑天然复用此窗。
    @MainActor
    static func presentFallbackMainWindow() {
        guard NSApp.windows.first(where: {
            $0.identifier?.rawValue.contains("main") == true && $0.isVisible
        }) == nil else { return }

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 200, y: 200, width: 1100, height: 720)
        let window = NSWindow(
            contentRect: NSRect(
                x: screen.midX - 390, y: screen.midY - 300,
                width: min(780, screen.width - 80), height: min(600, screen.height - 80)
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("main-AppWindow-fallback")
        window.title = "妙右"
        window.contentView = NSHostingView(rootView: makeMainWindowContent())
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct WindowActionCapture: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onAppear {
                WindowActionStorage.shared.capture(openWindow)
            }
    }
}

struct MainWindowCaptureView: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            capture(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        DispatchQueue.main.async {
            capture(nsView.window)
        }
    }

    private func capture(_ window: NSWindow?) {
        WindowActionStorage.shared.captureMainWindow(window)
        guard let window else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        window.appearance = nil
        guard !AppGroup.standardDefaults.bool(forKey: "compactPreferencesWindowV1") else { return }
        AppGroup.standardDefaults.set(true, forKey: "compactPreferencesWindowV1")
        let top = window.frame.maxY
        window.setContentSize(NSSize(width: 780, height: 600))
        if let visible = window.screen?.visibleFrame {
            let x = max(visible.minX, min(window.frame.minX, visible.maxX - window.frame.width))
            let y = max(visible.minY, min(top - window.frame.height, visible.maxY - window.frame.height))
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

}

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button(L10n.text("检查更新…", "Check for Updates…")) { AppUpdateService.shared.checkFromMenu() }
        }
        // 应用级开窗桥:菜单构建时注入 openWindow,主窗口不存在也能打开
        CommandGroup(replacing: .newItem) {
            OpenWindowBridge()
        }
        CommandGroup(replacing: .appTermination) {
            Button(L10n.text("退出妙右", "Quit MiaoRight")) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }

    }
}

/// Presents the result of a "Show result" action in a small, dismissible window,
/// reusing the editor's `TestOutputView`. A single reusable window is kept so
/// repeated actions don't stack windows.
@MainActor
final class ResultWindowPresenter {
    static let shared = ResultWindowPresenter()

    func present(_ result: ScriptExecutionResult) {
        ActionResultPresentation.shared.present(result)
        WindowActionStorage.shared.showMainWindow()
    }

}


/// 把 SwiftUI 的 openWindow 注入 WindowActionStorage(应用级,零窗口可用)
struct OpenWindowBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                WindowActionStorage.shared.commandsOpenWindow = { id in
                    openWindow(id: id)
                }
            }
    }
}
