import AppKit
import MiaoRightShared
import SwiftUI

struct FileOperationResultView: View {
    let result: ScriptExecutionResult
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(ActionNames.name(result.scriptName), systemImage: result.success ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button { ActionResultPresentation.shared.result = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel(L10n.text("关闭结果", "Dismiss Result"))
            }
            ScrollView {
                Text(result.success ? result.output : (result.error ?? L10n.text("操作失败", "Action failed")))
                    .font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 90)
            HStack(spacing: 14) {
                if !result.outputPaths.isEmpty {
                    Button(L10n.text("打开所在位置", "Show in Finder")) {
                        guard !AppGroup.isIsolated else { return }
                        let urls = result.outputPaths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
                        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
                    }.buttonStyle(.borderless)
                }
                if let id = result.undoID, let receipt = FileOperationJournal.shared.receipt(id) {
                    Button(L10n.text("撤销\(receipt.localizedTitle)", "Undo \(receipt.localizedTitle)")) { undo(id) }.buttonStyle(.borderless).disabled(busy)
                }
                if busy { ProgressView().controlSize(.small) }
            }.font(.system(size: 12))
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red).textSelection(.enabled) }
        }.padding(20)
    }

    private func undo(_ id: UUID) {
        busy = true; error = nil
        Task {
            let outcome = await Task.detached { () -> Result<[URL], ScriptError> in
                do { return .success(try FileOperationJournal.shared.undo(id)) }
                catch { return .failure(.executionFailed(error.localizedDescription)) }
            }.value
            busy = false
            switch outcome {
            case .success(let urls): ActionResultPresentation.shared.present(.success(scriptName: "已撤销", output: urls.map(\.path).joined(separator: "\n"), outputPaths: urls.map(\.path)))
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }
}
