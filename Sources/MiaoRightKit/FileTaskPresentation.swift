import Foundation
import MiaoRightShared
import Observation
import SwiftUI

@MainActor @Observable
final class FileTaskPresentation {
    static let shared = FileTaskPresentation()
    enum Kind: Sendable { case compress, rename }
    struct Request: Identifiable, Sendable {
        let id = UUID()
        let kind: Kind
        let urls: [URL]
        var encrypted = false
    }
    var request: Request?
    var isBusy = false
    var extractionProgress: Double?
    private var archiveWindow: NSWindow?
    private var extractionWindow: NSWindow?

    func present(_ kind: Kind, urls: [URL], encrypted: Bool = false) {
        guard !isBusy else { return }
        let task = Request(kind: kind, urls: urls, encrypted: encrypted)
        if kind == .compress, !AppGroup.isIsolated {
            closeArchiveWindow()
            archiveWindow = showArchiveWindow(encrypted ? L10n.text("加密压缩", "Encrypt and Compress") : L10n.text("压缩文件", "Compress Files"), content: FileTaskView(request: task) {
                self.closeArchiveWindow()
            }.frame(width: 400).fixedSize(horizontal: false, vertical: true))
            return
        }
        request = task
        if !AppGroup.isIsolated { WindowActionStorage.shared.showMainWindow() }
    }

    func showExtractionProgress() {
        extractionWindow = showArchiveWindow(L10n.text("正在解压", "Extracting"), content: ExtractionProgressView(tasks: self))
    }

    func closeExtractionProgress() {
        extractionWindow?.close()
        extractionWindow = nil
    }

    func closeArchiveWindow() {
        archiveWindow?.close()
        archiveWindow = nil
    }

    private func showArchiveWindow(_ title: String, content: some View) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.styleMask = [.titled]
        window.isReleasedWhenClosed = false
        window.title = title
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }
}

private struct ExtractionProgressView: View {
    let tasks: FileTaskPresentation

    var body: some View {
        Group {
            if let progress = tasks.extractionProgress {
                ProgressView(value: progress) { Text(L10n.text("正在解压…", "Extracting…")) }
            } else {
                ProgressView { Text(L10n.text("正在解压…", "Extracting…")) }
                    .progressViewStyle(.linear)
            }
        }
        .frame(width: 300)
        .padding(24)
    }
}
