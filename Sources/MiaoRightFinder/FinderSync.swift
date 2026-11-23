//
//  FinderSync.swift
//  MiaoRightFinder
//
//  Finder Sync Extension for MiaoRight(基于 MiaoRight 二次开发)
//

import Cocoa
import FinderSync
import os.log
import MiaoRightShared

private let logger = Logger(subsystem: "com.miaoright.app.FinderSync", category: "FinderSync")
private let openMainWindowNotification = NSNotification.Name("com.miaoright.openMainWindow")

/// Execution request written to App Group container for host app to process
struct ExecutionRequest: Codable {
    let scriptId: UUID
    let paths: [String]
    let timestamp: Date
    let requestId: UUID // Unique ID to prevent duplicate processing
    /// 动作附加参数,例如「移动到/复制到」的目标文件夹路径。
    let parameter: String?
    let workflowId: UUID?

    init(scriptId: UUID, paths: [String], timestamp: Date = Date(), requestId: UUID = UUID(), parameter: String? = nil, workflowId: UUID? = nil) {
        self.scriptId = scriptId
        self.paths = paths
        self.timestamp = timestamp
        self.requestId = requestId
        self.parameter = parameter
        self.workflowId = workflowId
    }
}

class FinderSync: FIFinderSync {
    /// Scripts available for current menu
    private var currentScripts: [ExtensionScript] = []

    private var scriptsFileURL: URL {
        guard let containerURL = AppGroup.containerURL else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return appSupport.appendingPathComponent("MiaoRight/scripts.json")
        }
        return containerURL.appendingPathComponent("scripts.json")
    }

    private var categoriesFileURL: URL {
        guard let containerURL = AppGroup.containerURL else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return appSupport.appendingPathComponent("MiaoRight/categories.json")
        }
        return containerURL.appendingPathComponent("categories.json")
    }

    override init() {
        super.init()
        logger.info("FinderSync extension init() called")

        reloadMonitoredFolders()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.reloadMonitoredFolders()
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(scriptsDidChange),
            name: NSNotification.Name("com.miaoright.scriptsChanged"),
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(monitoredFoldersDidChange),
            name: MonitoredFolders.changedNotification,
            object: nil
        )

    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func scriptsDidChange() {}

    @objc private func monitoredFoldersDidChange() {
        reloadMonitoredFolders()
    }


    private func reloadMonitoredFolders() {
        let urls = Set(MonitoredFolders.monitoredURLs())
        FIFinderSyncController.default().directoryURLs = urls
        logger.info("Reloaded monitored folders: \(urls.count)")
    }

    // MARK: - Context Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        logger.info("menu(for:) called with menuKind: \(String(describing: menuKind))")
        let menu = NSMenu(title: "妙右")
        // 显式控制启用状态:「粘贴」需按剪切状态灰显;分组标题保持不可点
        menu.autoenablesItems = false

        let scripts = loadScripts()
        let selectedURLs = resolvedSelectionURLs()
        let selectionCount = selectedURLs.count

        let applicable = scripts.filter { script in
            guard script.isEnabled else { return false }
            guard QuickMenuPlan.isAvailable(.init(id: script.id, name: script.name, icon: script.icon, content: script.content), resolveBundleID: {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
            }) else { return false }

            let menuKindMatch: Bool = switch menuKind {
            case .contextualMenuForItems:
                script.appliesTo == "Files & Folders" ||
                    script.appliesTo == "Files Only" ||
                    script.appliesTo == "Folders Only"
            case .contextualMenuForContainer:
                script.appliesTo == "Inside Folder" ||
                    script.appliesTo == "Files & Folders"
            case .contextualMenuForSidebar:
                script.appliesTo == "Folders Only" ||
                    script.appliesTo == "Files & Folders"
            default:
                false
            }

            guard menuKindMatch else { return false }
            guard script.matchesSelectionCount(selectionCount) else { return false }
            return script.matchesFiles(selectedURLs)
        }

        currentScripts = []
        let byID = Dictionary(uniqueKeysWithValues: applicable.map { ($0.id, $0) })
        let plan = QuickMenuPlan.sections(for: applicable.map {
            QuickMenuAction(id: $0.id, name: $0.name, icon: $0.icon, content: $0.content)
        })
        func append(_ entry: QuickMenuAction, to target: NSMenu, appTitle: Bool = false) {
            guard let script = byID[entry.id] else { return }
            let title = appTitle ? QuickMenuPlan.applicationTitle(entry) : QuickMenuPlan.title(entry)
            let item = NSMenuItem(title: title, action: #selector(executeScript(_:)), keyEquivalent: "")
            item.tag = currentScripts.count
            currentScripts.append(script)
            item.isEnabled = script.name != ActionID.paste || CutClipboard.load() != nil
            item.image = NSImage(systemSymbolName: entry.icon, accessibilityDescription: nil)
            if script.name == ActionID.deletePermanently {
                item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.systemRed])
            }
            target.addItem(item)
        }
        for section in plan {
            if let title = section.title {
                let submenu = NSMenu(title: title)
                submenu.autoenablesItems = false
                let isApps = section.actions.allSatisfy { QuickMenuPlan.isApplication(name: $0.name, content: $0.content) }
                for entry in section.actions { append(entry, to: submenu, appTitle: isApps) }
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.image = NSImage(systemSymbolName: section.icon, accessibilityDescription: nil)
                item.submenu = submenu
                menu.addItem(item)
            } else {
                for entry in section.actions { append(entry, to: menu) }
            }
        }

        if SharedDefaults.showOpenMainWindowMenuItem() {
            let settingsItem = NSMenuItem(
                title: L10n.text("打开妙右设置…", "Open MiaoRight Settings…"),
                action: #selector(openMainApp),
                keyEquivalent: ""
            )
            settingsItem.image = tintedSFSymbol(name: "gearshape", accessibilityDescription: "Settings")
            menu.addItem(settingsItem)
        }

        return menu
    }

    private func colorFromHex(_ hex: String) -> CGColor {
        var value: UInt64 = 0
        var hexString = hex
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        Scanner(string: hexString).scanHexInt64(&value)
        return CGColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: 1
        )
    }


    /// Build a script menu item. The `.tag` MUST equal the script's index in
    /// `currentScripts` (the applicable list); `executeScript(_:)` looks the
    /// script up by `currentScripts[sender.tag]`.
    private func makeScriptItem(_ script: ExtensionScript, index: Int) -> NSMenuItem {
        // 「移动到/复制到」动态子菜单:每个常用文件夹一个子项 + 选择其他文件夹…

        let item = NSMenuItem(title: ActionNames.name(script.name), action: #selector(executeScript(_:)), keyEquivalent: "")
        item.tag = index
        item.image = tintedSFSymbol(name: script.icon, accessibilityDescription: script.name)
        return item
    }



    @objc func executeScript(_ sender: AnyObject?) {
        submitExecution(from: sender, parameter: nil)
    }


    private func submitExecution(from sender: AnyObject?, parameter: String?) {
        guard let menuItem = sender as? NSMenuItem else { return }

        let tag = menuItem.tag
        guard tag >= 0, tag < currentScripts.count else { return }
        let script = currentScripts[tag]

        let items = resolvedSelectionURLs()
        guard !items.isEmpty else { return }
        let paths = items.map(\.path)

        guard let containerURL = AppGroup.containerURL else { return }

        let pendingURL = containerURL.appendingPathComponent("pending_execution.json")
        let request = ExecutionRequest(scriptId: script.id, paths: paths, parameter: parameter)

        do {
            let data = try JSONEncoder().encode(request)
            try data.write(to: pendingURL, options: .atomic)
        } catch {
            return
        }

        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.miaoright.executeScript"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        ensureHostAppRunning()
    }

    @objc func openMainApp() {
        let center = DistributedNotificationCenter.default()
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.miaoright.app").first {
            center.postNotificationName(openMainWindowNotification, object: nil, userInfo: nil, deliverImmediately: true)
            running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        } else {
            launchHostApp(activate: true)
            for delay in [0.75, 1.5, 3.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    center.postNotificationName(openMainWindowNotification, object: nil, userInfo: nil, deliverImmediately: true)
                }
            }
        }
    }

    private func ensureHostAppRunning() {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.miaoright.app")
        if running.isEmpty {
            launchHostApp(activate: false, executionRequested: true)
            for delay in [0.75, 1.5, 3.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    DistributedNotificationCenter.default().postNotificationName(
                        NSNotification.Name("com.miaoright.executeScript"),
                        object: nil,
                        userInfo: nil,
                        deliverImmediately: true
                    )
                }
            }
        }
    }

    private func launchHostApp(activate: Bool, executionRequested: Bool = false) {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.miaoright.app") {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = activate
            configuration.addsToRecentItems = false
            if executionRequested {
                configuration.arguments = ["--miaoright-execution-requested"]
            }
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        }
    }

    private func resolvedSelectionURLs() -> [URL] {
        let controller = FIFinderSyncController.default()
        let selected = controller.selectedItemURLs() ?? []
        if !selected.isEmpty {
            return selected
        }
        if let targeted = controller.targetedURL() {
            return [targeted]
        }
        return []
    }

    private func loadScripts() -> [ExtensionScript] {
        guard FileManager.default.fileExists(atPath: scriptsFileURL.path),
              let data = try? Data(contentsOf: scriptsFileURL),
              let scripts = try? JSONDecoder().decode([ExtensionScript].self, from: data)
        else {
            return []
        }
        return scripts
    }

    private func loadCategories() -> [ExtensionCategory] {
        guard FileManager.default.fileExists(atPath: categoriesFileURL.path),
              let data = try? Data(contentsOf: categoriesFileURL),
              let categories = try? JSONDecoder().decode([ExtensionCategory].self, from: data)
        else {
            return []
        }
        return categories
    }

    /// Render an SF Symbol as a tinted bitmap image.
    /// Finder forces template rendering on NSMenuItem images, so we rasterize
    /// with a palette color configuration to produce a non-template bitmap.
    private func tintedSFSymbol(name: String, accessibilityDescription: String?) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription) else {
            return nil
        }

        // Apply palette color so the symbol renders with a specific color
        let config = NSImage.SymbolConfiguration(paletteColors: [.controlAccentColor])
        guard let colored = symbol.withSymbolConfiguration(config) else { return nil }

        // Rasterize into a bitmap so Finder cannot re-template it
        let size = NSSize(width: 16, height: 16)
        let bitmap = NSImage(size: size, flipped: false) { rect in
            colored.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
        bitmap.isTemplate = false
        return bitmap
    }
}

// MARK: - Category Model

struct ExtensionCategory: Codable {
    let id: UUID
    let name: String
    let icon: String
}

// MARK: - Script Model

struct ExtensionScript: Codable {
    let id: UUID
    var name: String
    var type: String
    var content: String
    var isEnabled: Bool
    var icon: String
    var appliesTo: String
    var fileExtensions: [String]
    var extensionMatchMode: String
    var minSelection: Int
    var maxSelection: Int?
    var categoryId: UUID?
    /// Built-in library category name (a `ScriptLibrary.ScriptCategory.rawValue`),
    /// `nil` for purely custom actions and top-level actions (顶层动作在菜单最前)。
    var libraryCategory: String?

    enum CodingKeys: String, CodingKey {
        case id, name, type, content, isEnabled, icon, appliesTo, fileExtensions, extensionMatchMode, minSelection, maxSelection, categoryId, libraryCategory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(String.self, forKey: .type)
        content = try container.decode(String.self, forKey: .content)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        icon = try container.decode(String.self, forKey: .icon)
        appliesTo = try container.decode(String.self, forKey: .appliesTo)
        fileExtensions = try container.decodeIfPresent([String].self, forKey: .fileExtensions) ?? []
        extensionMatchMode = try container.decodeIfPresent(String.self, forKey: .extensionMatchMode) ?? "Any file matches"
        minSelection = try container.decodeIfPresent(Int.self, forKey: .minSelection) ?? 1
        maxSelection = try container.decodeIfPresent(Int.self, forKey: .maxSelection)
        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
        libraryCategory = try container.decodeIfPresent(String.self, forKey: .libraryCategory) ?? nil
    }

    func matchesFiles(_ urls: [URL]) -> Bool {
        let hasFiles = urls.contains { !$0.hasDirectoryPath }
        let hasFolders = urls.contains { $0.hasDirectoryPath }

        switch appliesTo {
        case "Files Only":
            guard hasFiles, !hasFolders else { return false }
        case "Folders Only", "Inside Folder":
            guard hasFolders, !hasFiles else { return false }
        default:
            break
        }

        guard !fileExtensions.isEmpty else { return true }

        let fileURLs = urls.filter { !$0.hasDirectoryPath }
        guard !fileURLs.isEmpty else {
            return false
        }

        let normalizedExtensions = Set(fileExtensions.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) })

        if extensionMatchMode == "Show only if all selected files match" {
            return fileURLs.allSatisfy { url in
                normalizedExtensions.contains(url.pathExtension.lowercased())
            }
        } else {
            return fileURLs.contains { url in
                normalizedExtensions.contains(url.pathExtension.lowercased())
            }
        }
    }

    func matchesSelectionCount(_ count: Int) -> Bool {
        if count < minSelection {
            return false
        }
        if let maxSelection, count > maxSelection {
            return false
        }
        return true
    }
}
