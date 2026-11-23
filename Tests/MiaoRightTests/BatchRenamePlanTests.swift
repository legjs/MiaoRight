import Foundation
import XCTest
@testable import MiaoRightKit

final class BatchRenamePlanTests: XCTestCase {
    private func files(_ names: [String]) throws -> [URL] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoRight-Rename-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return try names.map { name in
            let url = root.appendingPathComponent(name)
            try Data(name.utf8).write(to: url)
            return url
        }
    }

    func testPreviewReplacementsPreserveExtensionsAndOnlyApplyOnRequest() throws {
        let urls = try files(["报告2025.DOCX", "图片2025.PNG"])
        let plan = BatchRenamePlan(urls: urls, rule: .init(mode: .replace, search: "2025", replacement: "2026"))
        XCTAssertTrue(plan.canApply)
        XCTAssertEqual(plan.rows.map { $0.destination.lastPathComponent }, ["报告2026.DOCX", "图片2026.PNG"])
        XCTAssertTrue(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        let changed = try plan.apply(journal: FileOperationJournal())
        XCTAssertEqual(try String(contentsOf: changed[0], encoding: .utf8), "报告2025.DOCX")
    }

    func testConflictsInvalidNamesAndStalePreviewsNeverRenameFiles() throws {
        let urls = try files(["a.txt", "b.txt"])
        let collision = BatchRenamePlan(urls: [urls[0]], rule: .init(mode: .replace, search: "a", replacement: "b"))
        XCTAssertFalse(collision.canApply)
        XCTAssertThrowsError(try collision.apply())
        let invalid = BatchRenamePlan(urls: urls, rule: .init(mode: .affixes, prefix: "/"))
        XCTAssertFalse(invalid.canApply)
        let stale = BatchRenamePlan(urls: urls, rule: .init(mode: .affixes, prefix: "new-"))
        try Data("replaced file contents".utf8).write(to: urls[0])
        XCTAssertThrowsError(try stale.apply())
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: urls[0].deletingLastPathComponent().path)), ["a.txt", "b.txt"])
    }

    func testNumberingAndCaseOnlyRename() throws {
        let urls = try files(["PHOTO.JPG", "SECOND.JPG"])
        let numbered = BatchRenamePlan(urls: urls, rule: .init(mode: .sequence, baseName: "旅行", start: 7, digits: 3))
        XCTAssertEqual(numbered.rows.map { $0.destination.lastPathComponent }, ["旅行-007.JPG", "旅行-008.JPG"])
        let lower = BatchRenamePlan(urls: [urls[0]], rule: .init(mode: .lowercase))
        XCTAssertTrue(lower.canApply)
        let outputs = try lower.apply(journal: FileOperationJournal())
        XCTAssertEqual(outputs[0].lastPathComponent, "photo.JPG")
        XCTAssertEqual(try String(contentsOf: outputs[0], encoding: .utf8), "PHOTO.JPG")
    }
}
