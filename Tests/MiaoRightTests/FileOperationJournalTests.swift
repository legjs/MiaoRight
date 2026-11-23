import Foundation
import XCTest
@testable import MiaoRightKit

final class FileOperationJournalTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoRight-Undo-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    func testMoveCanBeUndoneWithoutChangingContents() throws {
        let root = try directory(), journal = FileOperationJournal(), id = UUID()
        let source = root.appendingPathComponent("原文件.txt"), destination = root.appendingPathComponent("新文件.txt")
        let bytes = Data("Keep these bytes".utf8)
        try bytes.write(to: source)
        try FileTaskContext.$executionID.withValue(id) {
            _ = try journal.perform([FileMove(source: source, destination: destination)], title: "Move")
            let summary = journal.summary(for: id)
            XCTAssertEqual(summary.outputPaths, [destination.path])
            let undoID = try XCTUnwrap(summary.undoID)
            XCTAssertEqual(try journal.undo(undoID), [source])
            XCTAssertEqual(try Data(contentsOf: source), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertNil(journal.receipt(undoID))
        }
    }

    func testUndoRefusesOccupiedOriginalPath() throws {
        let root = try directory(), journal = FileOperationJournal(), id = UUID()
        let source = root.appendingPathComponent("before"), destination = root.appendingPathComponent("after")
        try Data("original".utf8).write(to: source)
        try FileTaskContext.$executionID.withValue(id) {
            _ = try journal.perform([FileMove(source: source, destination: destination)], title: "Move")
            try Data("new user file".utf8).write(to: source)
            XCTAssertThrowsError(try journal.undo(try XCTUnwrap(journal.summary(for: id).undoID)))
            XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "new user file")
            XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "original")
        }
    }

    func testUndoRefusesModifiedDirectoryChildren() throws {
        let root = try directory(), journal = FileOperationJournal(), id = UUID()
        let source = root.appendingPathComponent("before", isDirectory: true), destination = root.appendingPathComponent("after", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try Data("first".utf8).write(to: source.appendingPathComponent("child"))
        try FileTaskContext.$executionID.withValue(id) {
            _ = try journal.perform([FileMove(source: source, destination: destination)], title: "Move")
            try Data("changed contents".utf8).write(to: destination.appendingPathComponent("child"))
            XCTAssertThrowsError(try journal.undo(try XCTUnwrap(journal.summary(for: id).undoID)))
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
            XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("child"), encoding: .utf8), "changed contents")
        }
    }

    func testSwappedNamesAndUndoPreserveBothFiles() throws {
        let root = try directory(), journal = FileOperationJournal(), id = UUID()
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        try Data("A".utf8).write(to: a); try Data("B".utf8).write(to: b)
        try FileTaskContext.$executionID.withValue(id) {
            _ = try journal.perform([FileMove(source: a, destination: b), FileMove(source: b, destination: a)], title: "Rename")
            XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "B")
            XCTAssertEqual(try String(contentsOf: b, encoding: .utf8), "A")
            _ = try journal.undo(try XCTUnwrap(journal.summary(for: id).undoID))
            XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "A")
            XCTAssertEqual(try String(contentsOf: b, encoding: .utf8), "B")
        }
    }

    func testMidOperationFailureRollsBackEveryStagedFile() throws {
        let root = try directory()
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        try Data("A".utf8).write(to: a); try Data("B".utf8).write(to: b)
        var calls = 0
        let journal = FileOperationJournal(moveItem: { source, destination in
            calls += 1
            if calls == 4 { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.moveItem(at: source, to: destination)
        })
        XCTAssertThrowsError(try journal.perform([FileMove(source: a, destination: root.appendingPathComponent("c")), FileMove(source: b, destination: root.appendingPathComponent("d"))], title: "Rename"))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), ["a", "b"])
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "A")
        XCTAssertEqual(try String(contentsOf: b, encoding: .utf8), "B")
    }

    func testMovingFolderIntoItselfIsRejectedBeforeAnyMutation() throws {
        let root = try directory()
        let folder = root.appendingPathComponent("source", isDirectory: true)
        let child = folder.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        var calls = 0
        let journal = FileOperationJournal(moveItem: { _, _ in calls += 1 })
        XCTAssertThrowsError(try journal.perform([FileMove(source: folder, destination: child.appendingPathComponent("source"))], title: "Move"))
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: child.path))
    }
}
