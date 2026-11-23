import Foundation
import MiaoRightShared
import Observation

/// 「加入保险箱」的内嵌确认流:与压缩/重命名共用主窗口替换式呈现。
@MainActor @Observable
final class VaultTaskPresentation {
    static let shared = VaultTaskPresentation()
    struct Request: Identifiable, Sendable {
        let id = UUID()
        let urls: [URL]
    }
    var request: Request?
    var isBusy = false

    func present(urls: [URL]) {
        guard !isBusy else { return }
        request = Request(urls: urls)
        if !AppGroup.isIsolated { WindowActionStorage.shared.showMainWindow() }
    }
}
