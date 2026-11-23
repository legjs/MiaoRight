import Foundation
@testable import MiaoRightKit
import MiaoRightShared
import XCTest

final class CutPasteRecoveryTests: XCTestCase {
    func testFailedPasteKeepsUnfinishedFilesAndAvoidsOverwriting() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let target = root.appendingPathComponent("target", isDirectory: true)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root); CutClipboard.clear() }
        let file = source.appendingPathComponent("example.txt")
        let missing = source.appendingPathComponent("missing.txt")
        try Data("new".utf8).write(to: file)
        let existing = target.appendingPathComponent("example.txt")
        try Data("existing".utf8).write(to: existing)
        CutClipboard.save(paths: [file.path, missing.path])
        do { _ = try NativeActionExecutor.pasteItems([target]); XCTFail("Missing file must report a failure") }
        catch { }
        XCTAssertEqual(CutClipboard.load()?.paths, [missing.path])
        XCTAssertFalse(fm.fileExists(atPath: file.path))
        XCTAssertEqual(try Data(contentsOf: existing), Data("existing".utf8))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: target.path).count, 2)
    }

    func testPastingIntoSameFolderDoesNotRenameOriginal() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder); CutClipboard.clear() }
        let file = folder.appendingPathComponent("original.txt")
        try Data("sample".utf8).write(to: file)
        CutClipboard.save(paths: [file.path])
        _ = try NativeActionExecutor.pasteItems([folder])
        XCTAssertTrue(fm.fileExists(atPath: file.path))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: folder.path), ["original.txt"])
        XCTAssertEqual(CutClipboard.load()?.paths, [file.path])
    }
}
