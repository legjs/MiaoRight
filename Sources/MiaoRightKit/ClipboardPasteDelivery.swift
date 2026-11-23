import AppKit
import MiaoRightShared

/// 粘贴只在面板交还焦点之后发生；测试注入环境，不访问真实输入与剪贴板。
@MainActor
final class ClipboardPasteDelivery {
    enum Outcome: Equatable { case pasted, permissionDenied, unavailable, changed, cancelled }
    @MainActor struct Environment {
        var authorized: @MainActor () -> Bool
        var clipboardVersion: @MainActor () -> Int
        var frontmostProcess: @MainActor () -> pid_t?
        var restoreTarget: @MainActor (pid_t) -> Bool
        var panelHasKey: @MainActor () -> Bool
        var postPaste: @MainActor (pid_t) -> Bool
        var pause: @MainActor () async -> Void

        static func live(panelHasKey: @escaping @MainActor () -> Bool) -> Self {
            Self(authorized: { AutoPaste.isAuthorized() },
                 clipboardVersion: { NSPasteboard.general.changeCount },
                 frontmostProcess: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
                 restoreTarget: { pid in
                     guard !AppGroup.isIsolated, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return false }
                     return app.activate(options: [])
                 }, panelHasKey: panelHasKey,
                 postPaste: { AutoPaste.paste(to: $0) },
                 pause: { try? await Task.sleep(for: .milliseconds(20)) })
        }
    }

    private let environment: Environment
    private var revision = 0
    init(environment: Environment) { self.environment = environment }
    func cancel() { revision += 1 }

    func deliver(to target: pid_t?, clipboardVersion: Int) async -> Outcome {
        let revision = revision
        guard environment.authorized() else { return .permissionDenied }
        guard let target else { return .unavailable }
        guard environment.clipboardVersion() == clipboardVersion else { return .changed }
        // 不打断已经切换到第三个应用的用户。
        let frontmost = environment.frontmostProcess()
        guard frontmost == target || frontmost == ProcessInfo.processInfo.processIdentifier else { return .changed }
        guard environment.restoreTarget(target) else { return .unavailable }
        var ready = false
        for _ in 0..<20 {
            await environment.pause()
            guard self.revision == revision, !Task.isCancelled else { return .cancelled }
            guard environment.authorized() else { return .permissionDenied }
            guard environment.clipboardVersion() == clipboardVersion else { return .changed }
            let frontmost = environment.frontmostProcess()
            guard frontmost == target || frontmost == ProcessInfo.processInfo.processIdentifier else { return .changed }
            if frontmost == target && !environment.panelHasKey() {
                if ready { return environment.postPaste(target) ? .pasted : .unavailable }
                ready = true
            } else { ready = false }
        }
        return .unavailable
    }
}

struct ClipboardListState {
    var selection = 0
    var picked: [UUID] = []
    mutating func beginPresentation() {
        selection = 0
        picked.removeAll()
    }
}
