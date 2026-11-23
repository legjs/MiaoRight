import Foundation

public struct MonitoredFolder: Codable, Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let path: String
    public let bookmarkData: Data

    public init(id: UUID = UUID(), name: String, path: String, bookmarkData: Data) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmarkData = bookmarkData
    }

    public var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }
}

public enum SharedDefaults {
    public static let showOpenMainWindowMenuItemKey = "showOpenMainWindowMenuItem"
    public static let foldersInRightClickMenuKey = "foldersInRightClickMenu"
    public static let frequentActionsPinnedKey = "frequentActionsPinned"

    public static var userDefaults: UserDefaults? {
        AppGroup.userDefaults
    }

    public static func registerDefaults(in defaults: UserDefaults? = userDefaults) {
        defaults?.register(defaults: [
            showOpenMainWindowMenuItemKey: true,
            foldersInRightClickMenuKey: true,
            frequentActionsPinnedKey: true
        ])
    }

    public static func showOpenMainWindowMenuItem(in defaults: UserDefaults? = userDefaults) -> Bool {
        defaults?.object(forKey: showOpenMainWindowMenuItemKey) as? Bool ?? true
    }

    public static func foldersInRightClickMenu(in defaults: UserDefaults? = userDefaults) -> Bool {
        defaults?.object(forKey: foldersInRightClickMenuKey) as? Bool ?? true
    }

    public static func frequentActionsPinned(in defaults: UserDefaults? = userDefaults) -> Bool {
        defaults?.object(forKey: frequentActionsPinnedKey) as? Bool ?? true
    }

    public static func setFrequentActionsPinned(_ value: Bool) {
        userDefaults?.set(value, forKey: frequentActionsPinnedKey)
    }
}

/// The built-in library categories, mirrored in Shared so the Finder extension and
/// the test target can resolve their display order and icons without importing the
/// host-app-only `ScriptLibrary.ScriptCategory` enum.
///
/// `rawValue` matches `ScriptLibrary.ScriptCategory.rawValue`, and `icon` mirrors
/// `ScriptLibrary.ScriptCategory.icon`. `displayOrder` lists them most-common first
/// (Essentials, Files & Folders, Images & Media, Coding, Advanced) so built-in
/// submenus lead the right-click menu ahead of any user-created categories.
public enum BuiltInMenuCategory: String, CaseIterable {
    case organize = "整理归档"
    case media = "图片处理"
    case share = "分享发送"
    case dev = "开发效率"
    case quickOpen = "快速打开"
    case utilities = "实用工具"

    public var icon: String {
        switch self {
        case .organize: "archivebox"
        case .media: "photo"
        case .share: "square.and.arrow.up"
        case .dev: "chevron.left.forwardslash.chevron.right"
        case .quickOpen: "arrow.up.forward.app"
        case .utilities: "wrench.and.screwdriver"
        }
    }

    /// 场景专属色(hex),用于菜单组头与界面卡片
    public var colorHex: String {
        switch self {
        case .organize: "#14B8A6"
        case .media: "#EC4899"
        case .share: "#F59E0B"
        case .dev: "#8B5CF6"
        case .quickOpen: "#0EA5E9"
        case .utilities: "#6366F1"
        }
    }

    public var emoji: String {
        switch self {
        case .organize: "📥"
        case .media: "🖼"
        case .share: "📤"
        case .dev: "💻"
        case .quickOpen: "🚀"
        case .utilities: "🧰"
        }
    }

    public var displayOrder: [String] { Self.allCases.map(\.rawValue) }

    public static func icon(forRawValue rawValue: String) -> String? {
        BuiltInMenuCategory(rawValue: rawValue)?.icon
    }
}

/// Pure grouping of applicable scripts into category folders for the right-click menu.
///
/// Lives in Shared so the Finder extension and the test target can both use it.
/// The result preserves the original index of each script (its position in the
/// applicable list) so the extension can keep menu item `.tag` == index, which is
/// what `executeScript(_:)` relies on to look the script up in `currentScripts`.
public enum RightClickMenuGrouping {
    /// One category folder plus the scripts that belong in it.
    public struct Folder<CategoryID: Hashable> {
        public let categoryId: CategoryID
        /// Script indices (into the original applicable list), in original order.
        public let scriptIndices: [Int]

        public init(categoryId: CategoryID, scriptIndices: [Int]) {
            self.categoryId = categoryId
            self.scriptIndices = scriptIndices
        }
    }

    /// Group `categoryIds` (one per applicable script, in order) into folders.
    ///
    /// - Parameters:
    ///   - categoryIds: the category id for each applicable script, by index. `nil` means uncategorized.
    ///   - orderedCategoryIds: all known category ids, in the order folders should appear.
    /// - Returns: folders in `orderedCategoryIds` order (only those with at least one
    ///   script), plus the indices of loose (uncategorized or unknown-category) scripts
    ///   in their original order.
    public static func group<CategoryID: Hashable>(
        categoryIds: [CategoryID?],
        orderedCategoryIds: [CategoryID]
    ) -> (folders: [Folder<CategoryID>], looseIndices: [Int]) {
        let knownIds = Set(orderedCategoryIds)
        var indicesByCategory: [CategoryID: [Int]] = [:]
        var looseIndices: [Int] = []

        for (index, categoryId) in categoryIds.enumerated() {
            if let categoryId, knownIds.contains(categoryId) {
                indicesByCategory[categoryId, default: []].append(index)
            } else {
                looseIndices.append(index)
            }
        }

        let folders = orderedCategoryIds.compactMap { categoryId -> Folder<CategoryID>? in
            guard let indices = indicesByCategory[categoryId], !indices.isEmpty else { return nil }
            return Folder(categoryId: categoryId, scriptIndices: indices)
        }

        return (folders, looseIndices)
    }

    /// Identifies where an applicable script's submenu should live.
    /// A script belongs to its USER category when it has one (`categoryId` that maps
    /// to a known user category); otherwise it falls back to its built-in
    /// `libraryCategory`. Scripts with neither are loose (top level).
    public struct ScriptCategoryAssignment {
        public let userCategoryId: UUID?
        /// `ScriptLibrary.ScriptCategory.rawValue` (built-in) when present.
        public let libraryCategory: String?

        public init(userCategoryId: UUID?, libraryCategory: String?) {
            self.userCategoryId = userCategoryId
            self.libraryCategory = libraryCategory
        }
    }

    /// One ordered submenu: a display title + icon plus the original indices of the
    /// applicable scripts inside it. `userCategoryId` is set for user categories,
    /// `nil` for built-in library categories.
    public struct MenuCategory {
        public let title: String
        public let icon: String
        public let userCategoryId: UUID?
        public let scriptIndices: [Int]

        public init(title: String, icon: String, userCategoryId: UUID?, scriptIndices: [Int]) {
            self.title = title
            self.icon = icon
            self.userCategoryId = userCategoryId
            self.scriptIndices = scriptIndices
        }
    }

    /// Build the ordered right-click submenu plan.
    ///
    /// Effective category per script: its user category (when `userCategoryId` maps
    /// to a known user category) ELSE its built-in `libraryCategory`. Built-in
    /// submenus come first in `BuiltInMenuCategory.displayOrder` (Essentials, Files &
    /// Folders, Images & Media, Coding, Advanced), then user categories in
    /// `orderedUserCategories` order, then loose/uncategorized indices at top level.
    /// Original indices are preserved so menu-item `.tag` == applicable-list index
    /// keeps working for `executeScript(_:)`.
    public static func menuPlan(
        assignments: [ScriptCategoryAssignment],
        orderedUserCategories: [(id: UUID, name: String, icon: String)]
    ) -> (categories: [MenuCategory], looseIndices: [Int]) {
        let knownUserIds = Set(orderedUserCategories.map(\.id))

        var builtInIndices: [String: [Int]] = [:]
        var userIndices: [UUID: [Int]] = [:]
        var looseIndices: [Int] = []

        for (index, assignment) in assignments.enumerated() {
            if let userId = assignment.userCategoryId, knownUserIds.contains(userId) {
                userIndices[userId, default: []].append(index)
            } else if let libraryCategory = assignment.libraryCategory,
                      BuiltInMenuCategory(rawValue: libraryCategory) != nil {
                builtInIndices[libraryCategory, default: []].append(index)
            } else {
                looseIndices.append(index)
            }
        }

        var categories: [MenuCategory] = []

        // Built-in categories first, in fixed most-common-first order.
        for builtIn in BuiltInMenuCategory.allCases {
            guard let indices = builtInIndices[builtIn.rawValue], !indices.isEmpty else { continue }
            categories.append(
                MenuCategory(
                    title: builtIn.rawValue,
                    icon: builtIn.icon,
                    userCategoryId: nil,
                    scriptIndices: indices
                )
            )
        }

        // Then user categories, in their configured order.
        for category in orderedUserCategories {
            guard let indices = userIndices[category.id], !indices.isEmpty else { continue }
            categories.append(
                MenuCategory(
                    title: category.name,
                    icon: category.icon,
                    userCategoryId: category.id,
                    scriptIndices: indices
                )
            )
        }

        return (categories, looseIndices)
    }
}

public struct MonitoredFolderAccessScope {
    private let urls: [URL]
    private let startedUrls: [URL]

    public init(urls: [URL], startedUrls: [URL]) {
        self.urls = urls
        self.startedUrls = startedUrls
    }

    public func stop() {
        for url in startedUrls {
            url.stopAccessingSecurityScopedResource()
        }
    }

    public var hasFullAccess: Bool {
        urls.count == startedUrls.count
    }
}

public enum MonitoredFolderError: LocalizedError, Equatable {
    case privacyScopedAppData(URL)

    public var errorDescription: String? {
        switch self {
        case .privacyScopedAppData:
            "Choose a normal folder such as Desktop, Documents, Downloads, or a project folder. macOS app-data folders inside Library are not supported because they can trigger repeated privacy prompts."
        }
    }
}

public enum MonitoredFolders {
    public static let appGroupID = "group.com.miaoright.app"
    public static let changedNotification = Notification.Name("com.miaoright.monitoredFoldersChanged")
    public static let monitoredFoldersConfiguredKey = "monitoredFoldersUserConfigured"

    private static var storageURL: URL {
        if let containerURL = AppGroup.containerURL {
            return containerURL.appendingPathComponent("monitored_folders.json")
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MiaoRight", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("monitored_folders.json")
    }

    private static var userDefaults: UserDefaults? {
        AppGroup.userDefaults
    }

    private static var hasUserConfiguredFolders: Bool {
        userDefaults?.bool(forKey: monitoredFoldersConfiguredKey) ?? false
    }

    private static var isRunningTests: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCTestSessionIdentifier"] != nil
    }

    public static func load() -> [MonitoredFolder] {
        let fileURL = storageURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return seedInitialDefaultFoldersIfNeeded()
        }

        guard let data = try? Data(contentsOf: fileURL),
              let folders = try? JSONDecoder().decode([MonitoredFolder].self, from: data)
        else {
            return seedInitialDefaultFoldersIfNeeded()
        }

        let validFolders = folders.filter { isSupportedMonitoredFolder(URL(fileURLWithPath: $0.path, isDirectory: true)) }
        if validFolders.count != folders.count {
            try? write(validFolders, markUserConfigured: false)
        }

        if validFolders.isEmpty, !hasUserConfiguredFolders {
            return seedInitialDefaultFoldersIfNeeded()
        }

        return validFolders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func save(_ folders: [MonitoredFolder]) throws {
        try write(folders, markUserConfigured: true)
    }

    private static func write(_ folders: [MonitoredFolder], markUserConfigured: Bool) throws {
        let data = try JSONEncoder().encode(folders)
        try data.write(to: storageURL, options: .atomic)
        if markUserConfigured {
            userDefaults?.set(true, forKey: monitoredFoldersConfiguredKey)
        }

        guard !AppGroup.isIsolated else { return }
        DistributedNotificationCenter.default().postNotificationName(
            changedNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    public static func paths() -> [String] {
        if monitorAllFoldersEnabled {
            return ["/"]
        }
        return load().map(\.path)
    }

    public static func monitoredURLs() -> [URL] {
        if monitorAllFoldersEnabled {
            // 根目录 + 显式枚举挂载卷:
            // Finder Sync 对「仅给 /」在外接盘/网络卷上不可靠,必须逐卷注册
            var urls = [URL(fileURLWithPath: "/", isDirectory: true)]
            let volumeNames = (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? []
            for name in volumeNames {
                let path = "/Volumes/" + name
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                    urls.append(URL(fileURLWithPath: path, isDirectory: true))
                }
            }
            return urls
        }
        return load().map(\.url)
    }

    /// 「在所有文件夹生效」开关(参考闪电右键的全局注入体验)。
    /// 开启后右键菜单在整个磁盘可用;关闭后仅在监控文件夹内生效。
    public static var monitorAllFoldersEnabled: Bool {
        get {
            userDefaults?.object(forKey: monitorAllFoldersKey) as? Bool ?? true
        }
        set {
            userDefaults?.set(newValue, forKey: monitorAllFoldersKey)
            guard !AppGroup.isIsolated else { return }
            DistributedNotificationCenter.default().postNotificationName(
                changedNotification,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        }
    }

    public static let monitorAllFoldersKey = "monitorAllFolders"

    @discardableResult
    public static func seedInitialDefaultFoldersIfNeeded() -> [MonitoredFolder] {
        guard !isRunningTests else { return [] }

        if FileManager.default.fileExists(atPath: storageURL.path),
           let data = try? Data(contentsOf: storageURL),
           let folders = try? JSONDecoder().decode([MonitoredFolder].self, from: data) {
            let validFolders = folders.filter { isSupportedMonitoredFolder(URL(fileURLWithPath: $0.path, isDirectory: true)) }
            if !validFolders.isEmpty || hasUserConfiguredFolders {
                return validFolders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }

        let folders = initialDefaultFolders()
        if !folders.isEmpty {
            try? write(folders, markUserConfigured: false)
        }
        return folders
    }

    public static func initialDefaultFolders(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [MonitoredFolder] {
        let home = homeDirectory.standardizedFileURL
        let candidates = [
            home.appendingPathComponent("Desktop", isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true),
            home.appendingPathComponent("Downloads", isDirectory: true),
            home.appendingPathComponent("Pictures", isDirectory: true),
            home.appendingPathComponent("Movies", isDirectory: true)
        ]

        return candidates
            .map(\.standardizedFileURL)
            .filter { isSupportedMonitoredFolder($0, homeDirectory: home) }
            .map { url in
                MonitoredFolder(
                    name: fileManager.displayName(atPath: url.path),
                    path: url.path,
                    bookmarkData: Data()
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func addFolder(url: URL, to existingFolders: [MonitoredFolder]) throws -> [MonitoredFolder] {
        let standardizedURL = url.standardizedFileURL
        guard isSupportedMonitoredFolder(standardizedURL) else {
            throw MonitoredFolderError.privacyScopedAppData(standardizedURL)
        }

        guard !existingFolders.contains(where: { $0.path == standardizedURL.path }) else {
            return existingFolders
        }

        let bookmarkData = try standardizedURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        var folders = existingFolders
        folders.append(
            MonitoredFolder(
                name: FileManager.default.displayName(atPath: standardizedURL.path),
                path: standardizedURL.path,
                bookmarkData: bookmarkData
            )
        )
        try save(folders)
        return load()
    }

    public static func isSupportedMonitoredFolder(_ url: URL, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let standardizedPath = url.standardizedFileURL.path
        let homePath = homeDirectory.standardizedFileURL.path
        let libraryPath = homePath + "/Library"

        guard standardizedPath != libraryPath,
              !standardizedPath.hasPrefix(libraryPath + "/")
        else {
            return false
        }

        return true
    }

    public static func removeFolder(id: UUID, from existingFolders: [MonitoredFolder]) throws -> [MonitoredFolder] {
        let filtered = existingFolders.filter { $0.id != id }
        try save(filtered)
        return load()
    }

    public static func beginAccess(for paths: [String]) -> MonitoredFolderAccessScope? {
        let folders = load()
        guard !folders.isEmpty else { return nil }

        let itemURLs = paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
        let matchingFolders = matchingFolders(for: itemURLs, in: folders)
        guard !matchingFolders.isEmpty else { return nil }

        let resolvedURLs = matchingFolders.compactMap(resolveBookmarkURL)
        let started = resolvedURLs.filter { $0.startAccessingSecurityScopedResource() }
        let scope = MonitoredFolderAccessScope(urls: resolvedURLs, startedUrls: started)
        guard scope.hasFullAccess else {
            scope.stop()
            return nil
        }
        return scope
    }

    private static func matchingFolders(for itemURLs: [URL], in folders: [MonitoredFolder]) -> [MonitoredFolder] {
        var matchesByPath: [String: MonitoredFolder] = [:]

        for itemURL in itemURLs {
            guard let folder = bestMatchingFolder(for: itemURL, in: folders) else {
                return []
            }
            matchesByPath[folder.path] = folder
        }

        return matchesByPath.values.sorted { $0.path < $1.path }
    }

    private static func bestMatchingFolder(for itemURL: URL, in folders: [MonitoredFolder]) -> MonitoredFolder? {
        let itemPath = itemURL.path

        return folders
            .filter { folder in
                itemPath == folder.path || itemPath.hasPrefix(folder.path + "/")
            }
            .max { lhs, rhs in
                lhs.path.count < rhs.path.count
            }
    }

    private static func resolveBookmarkURL(for folder: MonitoredFolder) -> URL? {
        var isStale = false

        guard let resolvedURL = try? URL(
            resolvingBookmarkData: folder.bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        return resolvedURL.standardizedFileURL
    }
}
