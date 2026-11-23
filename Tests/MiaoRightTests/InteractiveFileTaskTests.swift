import Foundation
import MiaoRightShared
import XCTest
@testable import MiaoRightKit

@MainActor
final class InteractiveFileTaskTests: XCTestCase {
    private func directory() throws -> URL {
        XCTAssertTrue(AppGroup.isIsolated)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoRight-Task-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    func testInteractiveActionsOnlyPrepareFormsBeforeConfirmation() async throws {
        let root = try directory()
        let file = root.appendingPathComponent("original.txt")
        try Data("unchanged".utf8).write(to: file)
        defer { FileTaskPresentation.shared.request = nil }
        for name in ["压缩…", "批量重命名…"] {
            let script = try XCTUnwrap(ScriptLibrary.libraryScript(named: name)).toScript()
            await ScriptExecutor.shared.execute(script: script, withPaths: [file.path])
            XCTAssertEqual(FileTaskPresentation.shared.request?.urls, [file])
            XCTAssertEqual(FileTaskPresentation.shared.request?.kind == .compress, name == "压缩…")
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["original.txt"])
            XCTAssertEqual(try Data(contentsOf: file), Data("unchanged".utf8))
        }
    }

    func testFavoriteMovePublishesLocationAndUndoThroughExecutor() async throws {
        let root = try directory()
        let folder = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let source = root.appendingPathComponent("original.txt")
        try Data("example".utf8).write(to: source)
        let shortcut = QuickFileShortcut(kind: .move, targetPath: folder.path, title: "Project")
        let script = Script(name: "Move Project", type: .composed, content: shortcut.encoded(), confirmBeforeRun: true)
        defer { ActionResultPresentation.shared.result = nil; ScriptExecutor.lastResult = nil }
        await ScriptExecutor.shared.execute(script: script, withPaths: [source.path])
        let result = try XCTUnwrap(ScriptExecutor.lastResult)
        XCTAssertTrue(result.success, result.error ?? "")
        XCTAssertEqual(result.outputPaths, [folder.appendingPathComponent(source.lastPathComponent).path])
        XCTAssertEqual(ActionResultPresentation.shared.result?.undoID, result.undoID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        _ = try FileOperationJournal.shared.undo(try XCTUnwrap(result.undoID))
        XCTAssertEqual(try Data(contentsOf: source), Data("example".utf8))
    }
}
