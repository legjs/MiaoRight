import AppKit
import Foundation
import MiaoRightShared
import SQLite3

/// SQLite 的 SQLITE_TRANSIENT 在 Swift 模块里没有直接暴露,标准变通定义
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 剪贴板历史的 SQLite 存储层。
/// 数据库与缩略图都落在「缓存目录」(设置页可改,默认
/// ~/Library/Application Support/MiaoRight/Clipboard);
/// 改目录 = 新库新开始(旧库留在原地不删,清除缓存才会删)。
///
/// 表结构:items(id TEXT PK, kind TEXT, content TEXT, date REAL)
/// 图片缩略图/原图存 <缓存目录>/thumbs/,条目 content 存文件名。
@MainActor
final class ClipboardStore {
    static let shared = ClipboardStore()

    // MARK: - 设置键

    static let cacheDirKey = "clipboardCacheDir"
    static let maxItemsKey = "clipboardMaxItems"
    static let defaultMaxItems = 100

    /// 当前缓存目录(确保存在)
    static var cacheDirectory: URL {
        let env = ProcessInfo.processInfo.environment
        if AppGroup.isIsolated || env["MIAORIGHT_CLIPBOARD_TEST_STORAGE"] != nil {
            let url = env["MIAORIGHT_CLIPBOARD_TEST_STORAGE"].map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? AppGroup.containerURLWithFallback.appendingPathComponent("Clipboard", isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let stored = AppGroup.standardDefaults.string(forKey: cacheDirKey)
        let url: URL
        if let stored, !stored.isEmpty {
            url = URL(fileURLWithPath: (stored as NSString).expandingTildeInPath)
        } else {
            url = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("MiaoRight/Clipboard", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var maxItems: Int {
        let stored = AppGroup.standardDefaults.integer(forKey: maxItemsKey)
        return stored > 0 ? stored : defaultMaxItems
    }

    static var databaseURL: URL { cacheDirectory.appendingPathComponent("clipboard.sqlite") }
    static var thumbsDirectory: URL {
        let dir = cacheDirectory.appendingPathComponent("thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - SQLite

    private var db: OpaquePointer?
    /// 目录变更后置空以触发重开
    private var openPath: String = ""

    private init() {}

    deinit {
        // MainActor 隔离下 deinit 不能直接触 db;泄漏一个连接句柄无碍
        // (进程结束自动回收),不在此关闭
    }

    private func openDB() -> Bool {
        let path = Self.databaseURL.path
        if db != nil, path == openPath { return true }
        if db != nil { sqlite3_close(db); db = nil }

        guard sqlite3_open(path, &db) == SQLITE_OK else {
            NSLog("[ClipboardStore] open failed: %s", path)
            if db != nil { sqlite3_close(db); db = nil }
            return false
        }
        openPath = path
        // WAL + 建表(幂等)
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        let create = """
        CREATE TABLE IF NOT EXISTS items(
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            content TEXT NOT NULL,
            date REAL NOT NULL,
            favorite INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_items_date ON items(date DESC);
        """
        guard sqlite3_exec(db, create, nil, nil, nil) == SQLITE_OK else {
            NSLog("[ClipboardStore] create table failed")
            return false
        }
        var schema: OpaquePointer?
        var hasFavorite = false
        if sqlite3_prepare_v2(db, "PRAGMA table_info(items)", -1, &schema, nil) == SQLITE_OK {
            while sqlite3_step(schema) == SQLITE_ROW {
                if let name = sqlite3_column_text(schema, 1), String(cString: name) == "favorite" { hasFavorite = true }
            }
        }
        sqlite3_finalize(schema)
        if !hasFavorite && sqlite3_exec(db, "ALTER TABLE items ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0", nil, nil, nil) != SQLITE_OK {
            NSLog("[ClipboardStore] favorite migration failed: \(errorMessage())")
            sqlite3_close(db); db = nil; openPath = ""
            return false
        }
        return true
    }

    private func errorMessage() -> String {
        db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
    }

    // MARK: - CRUD

    func loadAll() -> [ClipboardItem] {
        guard openDB() else { return [] }
        var items: [ClipboardItem] = []
        let query = "SELECT id, kind, content, date, favorite FROM items ORDER BY date DESC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            NSLog("[ClipboardStore] query failed: \(errorMessage())")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(stmt, 0),
                  let kindC = sqlite3_column_text(stmt, 1),
                  let contentC = sqlite3_column_text(stmt, 2)
            else { continue }
            let id = String(cString: idC)
            let kindRaw = String(cString: kindC)
            let content = String(cString: contentC)
            let date = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
            guard let kind = ClipboardKind(rawValue: kindRaw) else { continue }
            items.append(ClipboardItem(id: UUID(uuidString: id) ?? UUID(), kind: kind, content: content, date: date, isFavorite: sqlite3_column_int(stmt, 4) != 0))
        }
        return items
    }

    @discardableResult
    func upsert(_ item: ClipboardItem) -> Bool {
        guard openDB() else { return false }
        let sql = "INSERT INTO items(id,kind,content,date,favorite) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET kind=excluded.kind, content=excluded.content, date=excluded.date, favorite=excluded.favorite"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            NSLog("[ClipboardStore] upsert prepare failed: \(errorMessage())")
            return false
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, item.kind.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, item.content, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 4, item.date.timeIntervalSince1970)
        sqlite3_bind_int(stmt, 5, item.isFavorite ? 1 : 0)
        if sqlite3_step(stmt) != SQLITE_DONE {
            NSLog("[ClipboardStore] upsert failed: \(errorMessage())")
            return false
        }
        return true
    }

    func delete(id: UUID) {
        guard openDB() else { return }
        let sql = "DELETE FROM items WHERE id=?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        _ = sqlite3_step(stmt)
    }

    func setFavorite(id: UUID, value: Bool, refreshedDate: Date? = nil) -> Bool {
        guard openDB() else { return false }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE items SET favorite=?,date=COALESCE(?,date) WHERE id=?", -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, value ? 1 : 0)
        if let refreshedDate { sqlite3_bind_double(stmt, 2, refreshedDate.timeIntervalSince1970) }
        else { sqlite3_bind_null(stmt, 2) }
        sqlite3_bind_text(stmt, 3, id.uuidString, -1, SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_DONE && sqlite3_changes(db) == 1
    }

    /// 超出上限的尾部裁剪,返回被裁掉条目的 id(供调用方清理 thumbs)
    func trim(to limit: Int) -> [ClipboardItem] {
        guard openDB() else { return [] }
        // 先读出要删的
        var dropped: [ClipboardItem] = []
        let select = "SELECT id, kind, content, date FROM items WHERE favorite=0 ORDER BY date DESC LIMIT -1 OFFSET ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, select, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(stmt, 0),
                  let kindC = sqlite3_column_text(stmt, 1),
                  let contentC = sqlite3_column_text(stmt, 2),
                  let kind = ClipboardKind(rawValue: String(cString: kindC))
            else { continue }
            dropped.append(ClipboardItem(
                id: UUID(uuidString: String(cString: idC)) ?? UUID(),
                kind: kind,
                content: String(cString: contentC),
                date: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
            ))
        }
        dropped.forEach { delete(id: $0.id) }
        return dropped
    }

    /// 清空全部条目与 thumbs 文件(保留数据库文件本身)
    func clearAll() {
        guard openDB() else { return }
        sqlite3_exec(db, "DELETE FROM items;", nil, nil, nil)
        try? FileManager.default.removeItem(at: Self.thumbsDirectory)
    }

    /// 缓存占用估算(数据库 + thumbs)
    static func cacheSizeBytes() -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default
        if let dbAttrs = try? fm.attributesOfItem(atPath: databaseURL.path),
           let size = dbAttrs[.size] as? Int64 { total += size }
        ["-wal", "-shm"].forEach { suffix in
            if let a = try? fm.attributesOfItem(atPath: databaseURL.path + suffix),
               let s = a[.size] as? Int64 { total += s }
        }
        if let files = try? fm.contentsOfDirectory(at: thumbsDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for f in files {
                if let a = try? f.resourceValues(forKeys: [.fileSizeKey]), let s = a.fileSize {
                    total += Int64(s)
                }
            }
        }
        return total
    }

    // MARK: - thumbs 文件

    func thumbURL(name: String) -> URL? {
        let url = Self.thumbsDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func saveThumbPNG(_ data: Data, name: String) -> Bool {
        FileManager.default.createFile(
            atPath: Self.thumbsDirectory.appendingPathComponent(name).path,
            contents: data
        )
    }

    func saveOriginal(_ data: Data, name: String) -> Bool {
        FileManager.default.createFile(
            atPath: Self.thumbsDirectory.appendingPathComponent(name + ".orig").path,
            contents: data
        )
    }

    func originalData(name: String) -> Data? {
        try? Data(contentsOf: Self.originalImageURL(name: name))
    }

    static func originalImageURL(name: String) -> URL {
        thumbsDirectory.appendingPathComponent(name + ".orig")
    }

    func removeThumbFiles(name: String) {
        try? FileManager.default.removeItem(at: Self.thumbsDirectory.appendingPathComponent(name))
        try? FileManager.default.removeItem(at: Self.thumbsDirectory.appendingPathComponent(name + ".orig"))
    }

    // MARK: - 一次性迁移(旧 JSON → SQLite)

    /// 旧版 JSON(Application Support/MiaoRight/clipboard_history.json)导入后改名锚点
    static func migrateLegacyJSONIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        guard env["XCTestSessionIdentifier"] == nil, env["XCTestConfigurationFilePath"] == nil else { return }
        let legacy = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MiaoRight/clipboard_history.json")
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        if let data = try? Data(contentsOf: legacy),
           let old = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            let store = shared
            old.sorted(by: { $0.date < $1.date }).forEach { store.upsert($0) } // 旧→新插入,新在上
        }
        let anchor = legacy.deletingLastPathComponent().appendingPathComponent("clipboard_history.migrated.json")
        try? FileManager.default.removeItem(at: anchor)
        try? FileManager.default.moveItem(at: legacy, to: anchor)
    }
}
