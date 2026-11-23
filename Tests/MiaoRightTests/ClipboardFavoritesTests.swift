import Foundation
import MiaoRightShared
import SQLite3
import XCTest
@testable import MiaoRightKit

@MainActor
final class ClipboardFavoritesTests: XCTestCase {
    private func withStorage(_ body: (URL) throws -> Void) throws {
        XCTAssertTrue(AppGroup.isIsolated)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoRight-Favorites-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let previous = ProcessInfo.processInfo.environment["MIAORIGHT_CLIPBOARD_TEST_STORAGE"]
        setenv("MIAORIGHT_CLIPBOARD_TEST_STORAGE", root.path, 1)
        defer {
            if let previous { setenv("MIAORIGHT_CLIPBOARD_TEST_STORAGE", previous, 1) } else { unsetenv("MIAORIGHT_CLIPBOARD_TEST_STORAGE") }
            ClipboardHistoryService.shared.reloadStorage()
            try? FileManager.default.removeItem(at: root)
        }
        try body(root)
    }

    func testOldDatabaseAndJSONGainUnfavoritedDefaultWithoutLosingData() throws {
        try withStorage { root in
            var db: OpaquePointer?
            XCTAssertEqual(sqlite3_open(root.appendingPathComponent("clipboard.sqlite").path, &db), SQLITE_OK)
            let id = UUID()
            let sql = "CREATE TABLE items(id TEXT PRIMARY KEY,kind TEXT,content TEXT,date REAL); INSERT INTO items VALUES('\(id.uuidString)','text','legacy contents',\(Date().timeIntervalSince1970));"
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
            sqlite3_close(db)
            let items = ClipboardStore.shared.loadAll()
            XCTAssertEqual(items.map(\.content), ["legacy contents"])
            XCTAssertEqual(items.first?.isFavorite, false)
            XCTAssertTrue(ClipboardStore.shared.setFavorite(id: id, value: true))
            XCTAssertEqual(ClipboardStore.shared.loadAll().first?.isFavorite, true)
            let oldJSON = Data("{\"id\":\"\(id.uuidString)\",\"kind\":\"text\",\"content\":\"old\",\"date\":0}".utf8)
            XCTAssertFalse(try JSONDecoder().decode(ClipboardItem.self, from: oldJSON).isFavorite)
        }
    }

    func testFavoritesSurviveExpiryLimitsAndHistoryCleanup() throws {
        try withStorage { _ in
            let history = ClipboardHistoryService.shared
            history.setRetentionDays(0)
            let oldDate = Date().addingTimeInterval(-90 * 86400)
            let favorite = ClipboardItem(kind: .text, content: "keep favorite", date: oldDate, isFavorite: true)
            XCTAssertTrue(ClipboardStore.shared.upsert(favorite))
            XCTAssertTrue(ClipboardStore.shared.upsert(ClipboardItem(kind: .text, content: "expired", date: oldDate)))
            history.reloadStorage()
            history.setRetentionDays(7)
            XCTAssertEqual(history.items.map(\.id), [favorite.id])
            XCTAssertTrue(history.addFavoriteText("new favorite"))
            XCTAssertTrue(ClipboardStore.shared.upsert(ClipboardItem(kind: .text, content: "normal history")))
            history.reloadStorage()
            history.clearUnfavoritedHistory()
            XCTAssertEqual(Set(history.items.map(\.content)), ["keep favorite", "new favorite"])
            XCTAssertEqual(ClipboardStore.shared.trim(to: 0).count, 0)
            XCTAssertEqual(ClipboardStore.shared.loadAll().count, 2)
        }
    }

    func testUnfavoritingDoesNotImmediatelyExpireTheRecord() throws {
        try withStorage { _ in
            let history = ClipboardHistoryService.shared
            history.setRetentionDays(0)
            let item = ClipboardItem(kind: .text, content: "old favorite", date: Date().addingTimeInterval(-90 * 86400), isFavorite: true)
            XCTAssertTrue(ClipboardStore.shared.upsert(item))
            history.reloadStorage(); history.setRetentionDays(7)
            history.toggleFavorite(item)
            XCTAssertEqual(history.items.count, 1)
            XCTAssertFalse(try XCTUnwrap(history.items.first).isFavorite)
            XCTAssertGreaterThan(try XCTUnwrap(history.items.first).date, Date().addingTimeInterval(-5))
        }
    }

    func testFavoriteSnippetsDeduplicateAndPersistWithoutUsingClipboard() throws {
        try withStorage { _ in
            let history = ClipboardHistoryService.shared
            history.reloadStorage()
            XCTAssertTrue(history.addFavoriteText("Reusable address"))
            XCTAssertTrue(history.addFavoriteText("Reusable address"))
            XCTAssertEqual(history.items.count, 1)
            XCTAssertTrue(try XCTUnwrap(history.items.first).isFavorite)
            history.reloadStorage()
            XCTAssertEqual(history.items.map(\.content), ["Reusable address"])
            XCTAssertTrue(try XCTUnwrap(history.items.first).isFavorite)
            XCTAssertFalse(history.addFavoriteText(" \n "))
            XCTAssertFalse(history.addFavoriteText(String(repeating: "x", count: 10001)))
        }
    }

    func testRemovingHistoryPreservesImageFilesReferencedByFavorites() throws {
        try withStorage { _ in
            let history = ClipboardHistoryService.shared
            history.setRetentionDays(0)
            let name = "shared-image.png"
            let favorite = ClipboardItem(kind: .image, content: name, isFavorite: true)
            let normal = ClipboardItem(kind: .image, content: name)
            XCTAssertTrue(ClipboardStore.shared.upsert(favorite))
            XCTAssertTrue(ClipboardStore.shared.upsert(normal))
            XCTAssertTrue(ClipboardStore.shared.saveThumbPNG(Data("thumbnail".utf8), name: name))
            XCTAssertTrue(ClipboardStore.shared.saveOriginal(Data("original".utf8), name: name))
            history.reloadStorage()
            history.clearUnfavoritedHistory()
            XCTAssertEqual(history.items.map(\.id), [favorite.id])
            XCTAssertNotNil(ClipboardStore.shared.thumbURL(name: name))
            XCTAssertEqual(ClipboardStore.shared.originalData(name: name), Data("original".utf8))
            history.remove(favorite)
            XCTAssertNil(ClipboardStore.shared.thumbURL(name: name))
            XCTAssertNil(ClipboardStore.shared.originalData(name: name))
        }
    }
}
