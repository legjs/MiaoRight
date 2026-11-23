import AppKit
import Foundation
import MiaoRightShared

@MainActor
enum QuickFilePreferences {
    struct Folder: Identifiable {
        let url: URL
        let title: String
        let actions: [QuickFileShortcut.Kind: Script]
        var id: String { url.path }
        var isAvailable: Bool { QuickFileShortcut(kind: .openFolder, targetPath: url.path, title: title).isAvailable }
    }

    static func folders(in store: ScriptStore) -> [Folder] {
        var paths: [String] = []
        var titles: [String: String] = [:]
        var actions: [String: [QuickFileShortcut.Kind: Script]] = [:]
        for script in store.scripts {
            guard let shortcut = QuickFileShortcut(content: script.content), shortcut.kind != .template else { continue }
            if actions[shortcut.targetPath] == nil { paths.append(shortcut.targetPath) }
            titles[shortcut.targetPath] = shortcut.title
            actions[shortcut.targetPath, default: [:]][shortcut.kind] = script
        }
        return paths.map { Folder(url: URL(fileURLWithPath: $0), title: titles[$0] ?? "", actions: actions[$0] ?? [:]) }
    }

    static func templates(in store: ScriptStore) -> [Script] {
        store.scripts.filter { QuickFileShortcut(content: $0.content)?.kind == .template }
    }

    static func addFolder(_ url: URL, store: ScriptStore) throws {
        let url = url.resolvingSymlinksInPath().standardizedFileURL
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else {
            throw ScriptError.executionFailed(L10n.text("请选择可用的文件夹。", "Choose an available folder."))
        }
        guard !folders(in: store).contains(where: { $0.url == url }) else { return }
        let displayName = FileManager.default.displayName(atPath: url.path)
        let existingTitles = Set(folders(in: store).map(\.title))
        let title = existingTitles.contains(displayName) ? displayName + " · " + url.deletingLastPathComponent().path : displayName
        for kind in [QuickFileShortcut.Kind.openFolder, .copy, .move] {
            let shortcut = QuickFileShortcut(kind: kind, targetPath: url.path, title: title)
            store.addScript(Script(name: kind.menuTitle + " · " + title, type: .composed, content: shortcut.encoded(), icon: kind.icon,
                                   appliesTo: .allItems, confirmBeforeRun: kind == .move, libraryCategory: ScriptStore.topCategoryKey))
        }
    }

    static func removeFolder(_ folder: Folder, store: ScriptStore) {
        for script in folder.actions.values { store.deleteScript(script) }
    }

    static func templateRoot() -> URL { AppGroup.containerURLWithFallback.appendingPathComponent("FileTemplates", isDirectory: true) }

    static func addTemplate(_ source: URL, store: ScriptStore) throws {
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isPackageKey])
        guard values.isRegularFile == true || values.isPackage == true else {
            throw ScriptError.executionFailed(L10n.text("请选择文件或文档作为模板。", "Choose a file or document as a template."))
        }
        let folder = templateRoot().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent(source.lastPathComponent)
        do { try FileManager.default.copyItem(at: source, to: copy) }
        catch { try? FileManager.default.removeItem(at: folder); throw error }
        let baseName = source.deletingPathExtension().lastPathComponent
        let existingTitles = Set(templates(in: store).compactMap { QuickFileShortcut(content: $0.content)?.title })
        var title = baseName
        var suffix = 2
        while existingTitles.contains(title) { title = baseName + "-\(suffix)"; suffix += 1 }
        let shortcut = QuickFileShortcut(kind: .template, targetPath: copy.path, title: title)
        store.addScript(Script(name: QuickFileShortcut.Kind.template.menuTitle + " · " + title, type: .composed, content: shortcut.encoded(), icon: QuickFileShortcut.Kind.template.icon,
                               appliesTo: .allItems, maxSelection: 1, libraryCategory: ScriptStore.topCategoryKey))
    }

    static func removeTemplate(_ script: Script, store: ScriptStore) {
        // 只删除动作引用；保留快照，避免用户配置或旧操作仍引用它时丢失模板。
        store.deleteScript(script)
    }
}

enum QuickFileOperations {
    static func destinationFolder(for selected: URL) throws -> URL {
        let values = try selected.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values.isDirectory == true && values.isPackage != true ? selected : selected.deletingLastPathComponent()
    }

    static func folder(_ path: String) throws -> URL {
        guard path.hasPrefix("/") else { throw ScriptError.executionFailed(L10n.text("保存的文件夹路径无效。", "The saved folder path is invalid.")) }
        let url = URL(fileURLWithPath: path)
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else {
            throw ScriptError.executionFailed(L10n.text("保存的文件夹已不可用，请在设置中重新添加。", "The saved folder is unavailable. Add it again in settings."))
        }
        return url
    }

    static func createFromTemplate(_ template: URL, in folder: URL) throws -> URL {
        _ = try self.folder(folder.path)
        guard FileManager.default.fileExists(atPath: template.path) else {
            throw ScriptError.executionFailed(L10n.text("模板文件已丢失，请重新添加模板。", "The template is missing. Add it again."))
        }
        let destination = NativeActionExecutor.uniqueDestinationURL(
            in: folder, preferredName: template.deletingPathExtension().lastPathComponent, pathExtension: template.pathExtension
        )
        try FileManager.default.copyItem(at: template, to: destination)
        FileOperationJournal.shared.recordOutputs([destination])
        return destination
    }
}
