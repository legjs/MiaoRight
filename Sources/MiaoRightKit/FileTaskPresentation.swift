import Foundation
import MiaoRightShared
import Observation

@MainActor @Observable
final class FileTaskPresentation {
    static let shared = FileTaskPresentation()
    enum Kind: Sendable { case compress, rename }
    struct Request: Identifiable, Sendable {
        let id = UUID()
        let kind: Kind
        let urls: [URL]
    }
    var request: Request?
    var isBusy = false

    func present(_ kind: Kind, urls: [URL]) {
        guard !isBusy else { return }
        request = Request(kind: kind, urls: urls)
        if !AppGroup.isIsolated { WindowActionStorage.shared.showMainWindow() }
    }
}
