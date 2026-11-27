import AppKit
import MiaoRightShared
import SwiftUI

@MainActor
final class AppUpdatePromptPresenter: NSObject, NSWindowDelegate {
    static let shared = AppUpdatePromptPresenter()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func presentAvailable(_ release: GitHubRelease) {
        guard !AppGroup.isIsolated else { return }
        dismiss()
        let view = AppUpdateAvailableView(release: release) { [weak self] in
            self?.dismiss()
        }
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("软件更新", "Software Update")
        window.contentViewController = controller
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = true
        if let screen = screenForPrompt() {
            let visible = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            ))
        } else {
            window.center()
        }
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func presentUpToDate() {
        guard !AppGroup.isIsolated else { return }
        dismiss()
        showAlert(
            title: L10n.text("当前已是最新版本", "You're Up to Date"),
            message: L10n.text(
                "妙右 \(AppUpdateService.currentVersion) 已经是当前可用的最新版本。",
                "MiaoRight \(AppUpdateService.currentVersion) is the latest version available."
            ),
            button: L10n.text("好", "OK")
        )
    }

    func presentFailure(_ error: UpdateCheckError) {
        guard !AppGroup.isIsolated else { return }
        dismiss()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("检查更新失败", "Update Check Failed")
        alert.informativeText = error.message
        alert.addButton(withTitle: L10n.text("重试", "Try Again"))
        alert.addButton(withTitle: L10n.text("关闭", "Close"))
        centerAlert(alert)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await AppUpdateService.shared.checkAndPresentPrompt() }
        }
    }

    func presentNoRelease() {
        guard !AppGroup.isIsolated else { return }
        dismiss()
        showAlert(
            title: L10n.text("没有可用的更新", "No Update Available"),
            message: L10n.text(
                "暂未找到可匿名读取的稳定发行版本。",
                "No stable release is publicly readable right now."
            ),
            button: L10n.text("好", "OK")
        )
    }

    func dismiss() {
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        window = nil
    }

    private func showAlert(title: String, message: String, button: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        centerAlert(alert)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func screenForPrompt() -> NSScreen? {
        if let mainWindow = NSApp.mainWindow, mainWindow.isVisible, let screen = mainWindow.screen {
            return screen
        }
        if let mainWindow = NSApp.windows.first(where: {
            $0.isVisible && $0.identifier?.rawValue.contains("main") == true
        }), let screen = mainWindow.screen {
            return screen
        }
        if let mouseScreen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) {
            return mouseScreen
        }
        return NSScreen.main
    }

    private func centerAlert(_ alert: NSAlert) {
        alert.layout()
        guard let screen = screenForPrompt() else { return }
        let visible = screen.visibleFrame
        let size = alert.window.frame.size
        alert.window.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        ))
    }
}

private struct AppUpdateAvailableView: View {
    let release: GitHubRelease
    let onClose: () -> Void

    @State private var updates = AppUpdateService.shared
    @State private var isInstalling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                ReleaseNotesView(markdown: release.notes)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsInstallStatus {
                Divider()
                installStatus
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }

            Divider()
            footer
        }
        .frame(width: 560, height: 580)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.blue)
                Text(L10n.text("发现新版本 \(release.tagName)", "Version \(release.tagName) is available"))
                    .font(.system(size: 16, weight: .semibold))
                Spacer(minLength: 8)
            }
            Text(L10n.text("当前版本 \(AppUpdateService.currentVersion)", "Installed \(AppUpdateService.currentVersion)"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if updates.simulatesAvailableUpdate {
                Text(L10n.text("调试模拟：使用本地 v0.1.4 测试包", "Debug simulation: local v0.1.4 test package"))
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
        .padding(20)
    }

    private var showsInstallStatus: Bool {
        if case .idle = updates.installState { return false }
        return true
    }

    @ViewBuilder
    private var installStatus: some View {
        switch updates.installState {
        case .idle:
            EmptyView()
        case .downloading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(updates.simulatesAvailableUpdate
                    ? L10n.text("正在准备调试更新包…", "Preparing the debug update package…")
                    : L10n.text("正在下载更新…", "Downloading update…"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .verifying:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.text("正在校验更新包…", "Verifying update…"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.text("正在准备原位安装并重新启动…", "Preparing the in-place install and relaunch…"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !updates.canInstallInPlace {
                Text(L10n.text(
                    "请先把妙右放入应用程序文件夹，再使用自动安装。",
                    "Move MiaoRight to Applications before using automatic installation."
                ))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button(L10n.text("稍后", "Later")) { onClose() }
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 12)
                Button(L10n.text("发行页面", "Release Page")) {
                    NSWorkspace.shared.open(release.pageURL)
                }
                .buttonStyle(.borderless)
                if updates.canInstallInPlace {
                    Button(isInstalling || updates.isInstalling
                        ? L10n.text("正在更新…", "Updating…")
                        : L10n.text("更新到 \(release.tagName)", "Update to \(release.tagName)")) {
                        install()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isInstalling || updates.isInstalling)
                } else {
                    Button(L10n.text("打开发行页面", "Open Release Page")) {
                        NSWorkspace.shared.open(release.pageURL)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
    }

    private func install() {
        isInstalling = true
        Task {
            await updates.installUpdate(release)
            if case .failed = updates.installState {
                isInstalling = false
            }
        }
    }
}
