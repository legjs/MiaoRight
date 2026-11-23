import Foundation
import MiaoRightShared
import Observation
import os.log

private let storeLogger = Logger(subsystem: "com.miaoright.app", category: "ScriptStore")

enum ScriptImportMode: String, CaseIterable {
    case skipDuplicates
    case replaceDuplicates

    var title: String {
        switch self {
        case .skipDuplicates: "Skip duplicates"
        case .replaceDuplicates: "Replace duplicates"
        }
    }

    var detail: String {
        switch self {
        case .skipDuplicates: "Keep existing actions if names match"
        case .replaceDuplicates: "Overwrite existing actions with same name"
        }
    }
}

struct ScriptImportSummary {
    let added: Int
    let updated: Int
    let skipped: Int
    let categoriesAdded: Int

    var totalProcessed: Int {
        added + updated + skipped
    }
}

struct ScriptExportBundle: Codable {
    var schemaVersion: Int
    var app: String?
    var exportedAt: Date?
    var scripts: [Script]
    var categories: [ScriptCategory]

    init(scripts: [Script], categories: [ScriptCategory]) {
        schemaVersion = 1
        app = "MiaoRight"
        exportedAt = Date()
        self.scripts = scripts
        self.categories = categories
    }
}

/// Manages script configurations with file-based persistence
@Observable
@MainActor
public final class ScriptStore {
    public static let shared = ScriptStore()

    private(set) var scripts: [Script] = []
    private(set) var categories: [ScriptCategory] = []

    /// Whether there was an error loading data (shown in UI)
    private(set) var loadError: String?
    private var hasLoaded = false

    /// Shared file location via App Group container (accessible by both app and extension)
    private static var containerURL: URL? {
        // Tests run inside the host app process; isolate persistence to avoid
        // contention with extension/runtime files in the shared App Group path.
        if isRunningTests {
            return testStorageURL
        }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.miaoright.app")
    }

    private static var isRunningTests: Bool {
        AppGroup.isIsolated
    }

    private static var testStorageURL: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = ProcessInfo.processInfo.environment["MIAORIGHT_TEST_STORAGE"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? caches.appendingPathComponent("MiaoRightTests", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var scriptsFileURL: URL {
        guard let containerURL else {
            // Fallback to regular app support
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("MiaoRight", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("scripts.json")
        }
        return containerURL.appendingPathComponent("scripts.json")
    }

    private static var categoriesFileURL: URL {
        guard let containerURL else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("MiaoRight", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("categories.json")
        }
        return containerURL.appendingPathComponent("categories.json")
    }

    private init() {}

    public func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        loadCategories()
        loadScripts()
    }

    // MARK: - CRUD Operations

    func addScript(_ script: Script) {
        loadIfNeeded()
        scripts.append(script)
        saveScripts()
        notifyExtension()
    }

    func setLibraryScript(_ libraryScript: ScriptLibrary.LibraryScript, isEnabled: Bool) {
        loadIfNeeded()
        guard reconcileLibraryScript(libraryScript, isEnabled: isEnabled) else { return }
        saveScripts()
        notifyExtension()
    }

    func setLibraryScripts(_ libraryScripts: [ScriptLibrary.LibraryScript], isEnabled: Bool) {
        loadIfNeeded()
        var didChange = false
        for libraryScript in libraryScripts {
            didChange = reconcileLibraryScript(libraryScript, isEnabled: isEnabled) || didChange
        }
        guard didChange else { return }
        saveScripts()
        notifyExtension()
    }

    func updateScript(_ script: Script) {
        loadIfNeeded()
        guard let index = scripts.firstIndex(where: { $0.id == script.id }) else { return }
        scripts[index] = script
        saveScripts()
        notifyExtension()
    }

    func deleteScript(_ script: Script) {
        loadIfNeeded()
        scripts.removeAll { $0.id == script.id }
        saveScripts()
        notifyExtension()
    }

    func moveScript(from source: IndexSet, to destination: Int) {
        loadIfNeeded()
        scripts.move(fromOffsets: source, toOffset: destination)
        saveScripts()
        notifyExtension()
    }

    // MARK: - ScriptCategory CRUD Operations

    func addScriptCategory(_ category: ScriptCategory) {
        loadIfNeeded()
        categories.append(category)
        saveCategories()
    }

    func updateScriptCategory(_ category: ScriptCategory) {
        loadIfNeeded()
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        categories[index] = category
        saveCategories()
    }

    func deleteScriptCategory(_ category: ScriptCategory) {
        loadIfNeeded()
        // Move scripts in this category to uncategorized
        for index in scripts.indices where scripts[index].categoryId == category.id {
            scripts[index].categoryId = nil
        }
        categories.removeAll { $0.id == category.id }
        saveCategories()
        saveScripts()
        notifyExtension()
    }

    func moveScriptCategory(from source: IndexSet, to destination: Int) {
        loadIfNeeded()
        categories.move(fromOffsets: source, toOffset: destination)
        saveCategories()
    }

    // MARK: - Persistence

    private func loadScripts() {
        let fileURL = Self.scriptsFileURL

        // First launch - no file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            storeLogger.info("No scripts file found, creating defaults")
            scripts = createDefaultScripts()
            saveScripts()
            return
        }

        // Try to read the file
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            storeLogger.error("Failed to read scripts file: \(error.localizedDescription)")
            loadError = "Could not read scripts file: \(error.localizedDescription)"
            scripts = [] // Don't overwrite with defaults - preserve broken file for recovery
            return
        }

        // Try to decode
        do {
            scripts = try JSONDecoder().decode([Script].self, from: data)
            loadError = nil
            let loadedCount = scripts.count
            storeLogger.info("Loaded \(loadedCount) scripts")
            removeRetiredClipboardImageAction()
            applyLibraryDefaultsIfNeeded()
            backfillLibraryCategoriesIfNeeded()
            if normalizeLibraryScriptDuplicates() {
                saveScripts()
                notifyExtension()
            }
            addMissingLibraryScriptsIfNeeded()
            migrateOpenWithToQuickOpenIfNeeded()
        } catch {
            storeLogger.error("Failed to decode scripts: \(error.localizedDescription)")
            // Save corrupted file for recovery
            let backupURL = fileURL.deletingPathExtension().appendingPathExtension("corrupted.json")
            try? FileManager.default.removeItem(at: backupURL) // Remove old backup
            try? FileManager.default.copyItem(at: fileURL, to: backupURL)
            loadError = "Scripts file corrupted. Backup saved to: \(backupURL.lastPathComponent)"
            scripts = [] // Don't overwrite - let user decide
        }
    }

    @discardableResult
    private func reconcileLibraryScript(_ libraryScript: ScriptLibrary.LibraryScript, isEnabled: Bool) -> Bool {
        let matches = scripts.indices.filter {
            ActionCatalog.isLibraryRecord(scripts[$0], matching: libraryScript)
        }

        if matches.isEmpty {
            guard isEnabled else { return false }
            scripts.append(canonicalScript(from: libraryScript, isEnabled: true))
            return true
        }

        let canonicalIndex = matches[0]
        let existing = scripts[canonicalIndex]
        let canonical = canonicalScript(
            from: libraryScript,
            id: existing.id,
            isEnabled: isEnabled,
            categoryId: existing.categoryId,
            // 停用动作时打上时间戳(用于排序),重新启用则清空
            disabledAt: isEnabled ? nil : (existing.disabledAt ?? Date()),
            existing: existing
        )
        var didChange = scripts[canonicalIndex] != canonical
        scripts[canonicalIndex] = canonical

        for index in matches.dropFirst().reversed() {
            scripts.remove(at: index)
            didChange = true
        }

        return didChange
    }

    @discardableResult
    private func normalizeLibraryScriptDuplicates() -> Bool {
        var didChange = false

        for libraryScript in ScriptLibrary.allScripts {
            let matches = scripts.indices.filter {
                ActionCatalog.isLibraryRecord(scripts[$0], matching: libraryScript)
            }
            guard let canonicalIndex = matches.first else { continue }

            let shouldBeEnabled = matches.contains { scripts[$0].isEnabled }
            let canonical = canonicalScript(
                from: libraryScript,
                id: scripts[canonicalIndex].id,
                isEnabled: shouldBeEnabled,
                categoryId: scripts[canonicalIndex].categoryId,
                disabledAt: scripts[canonicalIndex].disabledAt,
                existing: scripts[canonicalIndex]
            )
            if scripts[canonicalIndex] != canonical {
                scripts[canonicalIndex] = canonical
                didChange = true
            }

            for index in matches.dropFirst().reversed() {
                scripts.remove(at: index)
                didChange = true
            }
        }

        return didChange
    }

    private func canonicalScript(
        from libraryScript: ScriptLibrary.LibraryScript,
        id: UUID = UUID(),
        isEnabled: Bool,
        categoryId: UUID? = nil,
        disabledAt: Date? = nil,
        existing: Script? = nil
    ) -> Script {
        Script(
            id: id,
            name: libraryScript.name,
            type: libraryScript.type,
            content: libraryScript.content,
            isEnabled: isEnabled,
            disabledAt: disabledAt,
            icon: libraryScript.icon,
            appliesTo: libraryScript.appliesTo,
            fileExtensions: libraryScript.fileExtensions,
            extensionMatchMode: libraryScript.extensionMatchMode,
            minSelection: libraryScript.minSelection,
            maxSelection: libraryScript.maxSelection,
            categoryId: categoryId,
            outputMode: existing?.outputMode ?? libraryScript.outputMode,
            confirmBeforeRun: libraryScript.confirmBeforeRun || (existing?.confirmBeforeRun ?? false),
            // 归属分类:保留用户改写值;未改写时跟随内置定义
            libraryCategory: existing?.libraryCategory ?? libraryScript.category?.rawValue
        )
    }

    private static let ioQueue = DispatchQueue(label: "com.miaoright.scripts.io", qos: .userInitiated)

    /// 「顶层」归属的存储键:写入 libraryCategory 后,右键菜单分组会把它
    /// 视为未知分类而自然落到顶层
    public static let topCategoryKey = "__top__"

    /// 迁移器专用:批量追加组合菜单(旧工作流翻译),一次落盘
    func appendScriptsForMigration(_ newScripts: [Script]) {
        guard !newScripts.isEmpty else { return }
        scripts.append(contentsOf: newScripts)
        saveScripts()
        notifyExtension()
    }

    /// 调整动作的归属分类:顶层传 topCategoryKey,场景传 BuiltInMenuCategory.rawValue。
    /// 归属变更会同步到右键菜单分组(保存 + 通知扩展)。
    public func setLibraryCategory(actionName: String, category: String?) {
        loadIfNeeded()
        guard let index = scripts.firstIndex(where: { $0.name == actionName }) else { return }
        scripts[index].libraryCategory = category
        saveScripts()
        notifyExtension()
    }

    /// 普通(非 atomic)写盘:.atomic 会走 Foundation 的受保护临时文件路径,
    /// 在 App Group 容器上可能因保护密钥/溯源服务停顿而无限阻塞 open(2)。
    /// 这些文件都很小且有备份轮换,非原子写入的损坏风险可忽略。
    nonisolated private static func writePlain(_ data: Data, to url: URL) -> Bool {
        FileManager.default.createFile(atPath: url.path, contents: data, attributes: nil)
    }

    private func saveScripts() {
        let fileURL = Self.scriptsFileURL

        // Encode data first - fail fast if encoding fails
        let data: Data
        do {
            data = try JSONEncoder().encode(scripts)
        } catch {
            storeLogger.error("Failed to encode scripts: \(error.localizedDescription)")
            return
        }

        // 备份与写入都在后台队列:文件系统偶发停顿时绝不阻塞主线程
        let backupURL = fileURL.deletingPathExtension().appendingPathExtension("backup.json")
        Self.ioQueue.async { [data] in
            if let old = try? Data(contentsOf: fileURL) {
                Self.writePlain(old, to: backupURL)
            }
            if Self.writePlain(data, to: fileURL) {
                storeLogger.info("Saved \(data.count) bytes of scripts")
            } else {
                storeLogger.error("CRITICAL: Failed to save scripts to \(fileURL.path)")
            }
        }
    }

    private func applyLibraryDefaultsIfNeeded() {
        let libraryByName = Dictionary(uniqueKeysWithValues: ScriptLibrary.allScripts.map { ($0.name, $0) })
        var updatedScripts = scripts
        var didUpdateAny = false

        for index in updatedScripts.indices {
            let script = updatedScripts[index]
            guard let library = libraryByName[script.name] else { continue }
            guard script.type == library.type, script.content == library.content else { continue }

            var updated = script
            var didUpdateScript = false

            if script.fileExtensions.isEmpty, !library.fileExtensions.isEmpty {
                updated.fileExtensions = library.fileExtensions
                didUpdateScript = true
            }

            if script.extensionMatchMode == .any, library.extensionMatchMode != .any {
                updated.extensionMatchMode = library.extensionMatchMode
                didUpdateScript = true
            }

            if script.minSelection == 1, script.maxSelection == nil {
                if library.minSelection != 1 || library.maxSelection != nil {
                    updated.minSelection = library.minSelection
                    updated.maxSelection = library.maxSelection
                    didUpdateScript = true
                }
            }

            if didUpdateScript {
                updatedScripts[index] = updated
                didUpdateAny = true
            }
        }

        if didUpdateAny {
            scripts = updatedScripts
            saveScripts()
            notifyExtension()
        }
    }

    private func removeRetiredClipboardImageAction() {
        let count = scripts.count
        scripts.removeAll {
            $0.name == "将剪贴板图片保存到这里"
                && $0.type == .bash
                && $0.content == "# Runs natively via MiaoRight (Save clipboard image)."
        }
        if scripts.count != count {
            saveScripts()
            notifyExtension()
        }
    }

    /// One-time, idempotent upgrade migration: stamp each built-in action that
    /// predates the `libraryCategory` field with its library category name so the
    /// Finder right-click menu can group existing users' built-ins into submenus
    /// (the same way fresh installs already carry it via `toScript()`).
    ///
    /// Only fills in a `nil` `libraryCategory`, and only when the installed record
    /// actually matches the library action by name/type/content (`isLibraryRecord`),
    /// so a user's custom action that happens to share a built-in name is left alone.
    /// This is metadata only — it does not touch identity or the native-action match,
    /// so guardrails are unaffected.
    private func backfillLibraryCategoriesIfNeeded() {
        let (migrated, didChange) = Self.backfillingLibraryCategories(scripts)
        guard didChange else { return }
        scripts = migrated
        saveScripts()
        notifyExtension()
    }

    /// Pure, idempotent migration used by `backfillLibraryCategoriesIfNeeded()`.
    /// Returns the scripts with built-in `libraryCategory` stamped in, and whether
    /// anything changed. Exposed (not private) so tests can exercise it directly
    /// without driving the singleton's one-shot disk load.
    static func backfillingLibraryCategories(_ scripts: [Script]) -> (scripts: [Script], didChange: Bool) {
        let libraryByName = Dictionary(uniqueKeysWithValues: ScriptLibrary.allScripts.map { ($0.name, $0) })
        var result = scripts
        var didChange = false

        for index in result.indices {
            guard result[index].libraryCategory == nil,
                  let library = libraryByName[result[index].name],
                  ActionCatalog.isLibraryRecord(result[index], matching: library)
            else { continue }

            result[index].libraryCategory = library.category?.rawValue
            didChange = true
        }

        return (result, didChange)
    }

    /// 升级迁移:「打开应用」组拆分到「快速打开」场景。
    /// 仅当记录归属仍是旧默认(开发效率/nil)时改写;用户改过归属的不动。幂等。
    private func migrateOpenWithToQuickOpenIfNeeded() {
        let quickOpen = BuiltInMenuCategory.quickOpen.rawValue
        let legacyDev = BuiltInMenuCategory.dev.rawValue
        let openWithNames = Set(ScriptLibrary.scripts(for: .quickOpen).map(\.name))
        var didChange = false
        for index in scripts.indices where openWithNames.contains(scripts[index].name) {
            let current = scripts[index].libraryCategory
            if current == nil || current == legacyDev {
                scripts[index].libraryCategory = quickOpen
                didChange = true
            }
        }
        if didChange {
            saveScripts()
            notifyExtension()
        }
    }

    /// 升级迁移:新版本动作库新增的动作自动补进本地(默认关闭,可在动作库中按需开启)
    private func addMissingLibraryScriptsIfNeeded() {
        let existingNames = Set(scripts.map(\.name))
        let missing = ScriptLibrary.allScripts.filter { !existingNames.contains($0.name) }
        guard !missing.isEmpty else { return }

        for library in missing {
            scripts.append(canonicalScript(from: library, isEnabled: false))
        }
        saveScripts()
        notifyExtension()
    }

    private func loadCategories() {
        let fileURL = Self.categoriesFileURL

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            categories = []
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            categories = try JSONDecoder().decode([ScriptCategory].self, from: data)
            let loadedCount = categories.count
            storeLogger.info("Loaded \(loadedCount) categories")
        } catch {
            storeLogger.error("Failed to load categories: \(error.localizedDescription)")
            categories = []
        }
    }

    private func saveCategories() {
        let fileURL = Self.categoriesFileURL

        let data: Data
        do {
            data = try JSONEncoder().encode(categories)
        } catch {
            storeLogger.error("Failed to encode categories: \(error.localizedDescription)")
            return
        }

        // 备份与写入后台化(同 saveScripts)
        let savedCount = categories.count
        let backupURL = fileURL.deletingPathExtension().appendingPathExtension("backup.json")
        Self.ioQueue.async { [data, savedCount] in
            if let old = try? Data(contentsOf: fileURL) {
                Self.writePlain(old, to: backupURL)
            }
            if Self.writePlain(data, to: fileURL) {
                storeLogger.info("Saved \(savedCount) categories")
            } else {
                storeLogger.error("Failed to save categories to \(fileURL.path)")
            }
        }
    }

    // MARK: - Import / Export

    func exportScripts(to url: URL) throws {
        loadIfNeeded()
        let bundle = ScriptExportBundle(scripts: scripts, categories: categories)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(bundle)
        try data.write(to: url, options: .atomic)
    }

    func importScripts(from url: URL, mode: ScriptImportMode) throws -> ScriptImportSummary {
        loadIfNeeded()
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let scriptsToImport: [Script]
        let categoriesToImport: [ScriptCategory]

        if let bundle = try? decoder.decode(ScriptExportBundle.self, from: data) {
            scriptsToImport = bundle.scripts
            categoriesToImport = bundle.categories
        } else {
            scriptsToImport = try decoder.decode([Script].self, from: data)
            categoriesToImport = []
        }

        var categoriesAdded = 0
        var existingById = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var existingByName = Dictionary(uniqueKeysWithValues: categories.map { ($0.name.lowercased(), $0) })
        var categoryIdMap: [UUID: UUID] = [:]

        if !categoriesToImport.isEmpty {
            for category in categoriesToImport {
                if category.id == ScriptCategory.uncategorized.id {
                    continue
                }

                if let existing = existingById[category.id] {
                    categoryIdMap[category.id] = existing.id
                    continue
                }

                if let existing = existingByName[category.name.lowercased()] {
                    categoryIdMap[category.id] = existing.id
                    continue
                }

                categories.append(category)
                existingById[category.id] = category
                existingByName[category.name.lowercased()] = category
                categoryIdMap[category.id] = category.id
                categoriesAdded += 1
            }

            if categoriesAdded > 0 {
                saveCategories()
            }
        }

        var added = 0
        var updated = 0
        var skipped = 0

        var indexById = [UUID: Int]()
        var indexByName = [String: Int]()

        for (index, script) in scripts.enumerated() {
            indexById[script.id] = index
            if QuickFileShortcut(content: script.content) == nil { indexByName[script.name.lowercased()] = index }
        }

        for script in scriptsToImport {
            var incoming = script
            if let categoryId = incoming.categoryId {
                if categoryId == ScriptCategory.uncategorized.id {
                    incoming.categoryId = nil
                } else if let mapped = categoryIdMap[categoryId] {
                    incoming.categoryId = mapped
                } else if existingById[categoryId] == nil {
                    incoming.categoryId = nil
                }
            }

            if let index = indexById[incoming.id] {
                if mode == .replaceDuplicates {
                    scripts[index] = incoming
                    updated += 1
                } else {
                    skipped += 1
                }
                continue
            }

            if QuickFileShortcut(content: incoming.content) == nil, let index = indexByName[incoming.name.lowercased()] {
                if mode == .replaceDuplicates {
                    let existingId = scripts[index].id
                    let replacement = Script(
                        id: existingId,
                        name: incoming.name,
                        type: incoming.type,
                        content: incoming.content,
                        isEnabled: incoming.isEnabled,
                        icon: incoming.icon,
                        appliesTo: incoming.appliesTo,
                        fileExtensions: incoming.fileExtensions,
                        extensionMatchMode: incoming.extensionMatchMode,
                        minSelection: incoming.minSelection,
                        maxSelection: incoming.maxSelection,
                        categoryId: incoming.categoryId
                    )
                    scripts[index] = replacement
                    indexByName[replacement.name.lowercased()] = index
                    updated += 1
                } else {
                    skipped += 1
                }
                continue
            }

            scripts.append(incoming)
            let newIndex = scripts.count - 1
            indexById[incoming.id] = newIndex
            if QuickFileShortcut(content: incoming.content) == nil { indexByName[incoming.name.lowercased()] = newIndex }
            added += 1
        }

        if added > 0 || updated > 0 {
            saveScripts()
            notifyExtension()
        }

        return ScriptImportSummary(
            added: added,
            updated: updated,
            skipped: skipped,
            categoriesAdded: categoriesAdded
        )
    }

    private func notifyExtension() {
        guard !AppGroup.isIsolated else { return }
        // Notify the Finder Sync Extension that scripts have changed
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.miaoright.scriptsChanged"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    /// 首次启动:写入完整内置动作库,并默认开启常用的一组动作。
    private func createDefaultScripts() -> [Script] {
        ScriptLibrary.allScripts.map { library in
            canonicalScript(
                from: library,
                isEnabled: ScriptLibrary.defaultEnabledActions.contains(library.name)
            )
        }
    }
}

// MARK: - Extension Helpers

extension ScriptStore {
    /// Get scripts that apply to a specific menu kind
    func scripts(for appliesTo: AppliesTo) -> [Script] {
        loadIfNeeded()
        return scripts.filter { $0.isEnabled && ($0.appliesTo == appliesTo || $0.appliesTo == .allItems) }
    }

    /// Get all enabled scripts
    var enabledScripts: [Script] {
        loadIfNeeded()
        return scripts.filter(\.isEnabled)
    }

    /// Get scripts for a specific category
    func scripts(in category: ScriptCategory?) -> [Script] {
        loadIfNeeded()
        if let category {
            return scripts.filter { $0.categoryId == category.id }
        } else {
            // Uncategorized scripts
            return scripts.filter { $0.categoryId == nil }
        }
    }

    /// Get scripts that are uncategorized
    var uncategorizedScripts: [Script] {
        loadIfNeeded()
        return scripts.filter { $0.categoryId == nil }
    }
}
