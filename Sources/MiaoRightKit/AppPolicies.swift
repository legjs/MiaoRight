import AppKit
import MiaoRightShared
import ServiceManagement

/// 应用行为策略:登录自启与 Dock/菜单栏形态。
/// 登录项只由用户显式开启，交由 ServiceManagement 判断是否允许注册。
enum AppPolicies {
    // MARK: - 默认值

    static let showDockIconDefault = false

    enum LoginItemState: Equatable {
        case disabled, enabled, requiresApproval, unavailable
        var isRequested: Bool { self == .enabled || self == .requiresApproval }
    }

    // MARK: - 登录自启

    static func loginItemState(
        statusProvider: () -> SMAppService.Status = { SMAppService.mainApp.status }
    ) -> LoginItemState {
        switch statusProvider() {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .disabled
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    enum LoginItemError: LocalizedError {
        case appBundleRequired
        var errorDescription: String? {
            L10n.text("请通过妙右 App 启动程序后再设置登录启动。", "Launch the MiaoRight app before configuring launch at login.")
        }
    }

    static func setLoginItemEnabled(
        _ enabled: Bool,
        bundleURL: URL = Bundle.main.bundleURL,
        register: () throws -> Void = { try SMAppService.mainApp.register() },
        unregister: () throws -> Void = { try SMAppService.mainApp.unregister() }
    ) throws {
        guard bundleURL.pathExtension.lowercased() == "app" else { throw LoginItemError.appBundleRequired }
        if enabled { try register() } else { try unregister() }
    }

    static func openLoginItemSettings() { SMAppService.openSystemSettingsLoginItems() }

    // MARK: - 激活策略(Dock 图标形态)

    /// 启动时应用策略:带重试,处理 AppKit 初始化时序
    @MainActor
    static func applyInitialPolicy(showDockIcon: Bool) {
        Task { @MainActor in
            enforcePolicy(showDockIcon: showDockIcon, retries: 10)
        }
    }

    /// 设置切换时立即应用
    @MainActor
    static func applyPolicy(showDockIcon: Bool) {
        let policy: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        NSApp.setActivationPolicy(policy)
        if showDockIcon {
            NSApp.activate()
        }
    }

    @MainActor
    private static func enforcePolicy(showDockIcon: Bool, retries: Int) {
        guard let app = NSApp else {
            guard retries > 0 else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                enforcePolicy(showDockIcon: showDockIcon, retries: retries - 1)
            }
            return
        }

        let policy: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        if app.activationPolicy() != policy {
            app.setActivationPolicy(policy)
        }

        guard retries > 0 else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            enforcePolicy(showDockIcon: showDockIcon, retries: retries - 1)
        }
    }
}
