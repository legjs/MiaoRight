import AppKit
import MiaoRightShared

/// 界面操作的适配层;复用已有动作与执行器,不拼接 shell 命令。
@MainActor
enum QuickAccessPreferences {
    static let bundles = QuickMenuPlan.applicationBundleIDs

    static func isAvailable(_ script: Script) -> Bool {
        QuickMenuPlan.isAvailable(model(script)) { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    }

    static func applicationURL(for script: Script) -> URL? {
        if let path = QuickMenuPlan.applicationPath(in: script.content) {
            return URL(fileURLWithPath: path)
        }
        return (bundles[script.name] ?? []).compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    static func isCore(_ script: Script) -> Bool {
        QuickFileShortcut(content: script.content) != nil || script.name == "复制路径" || [ActionID.cut, ActionID.paste].contains(script.name)
            || QuickMenuPlan.terminalNames.contains(script.name)
            || QuickMenuPlan.isApplication(name: script.name, content: script.content)
    }

    static func model(_ script: Script) -> QuickMenuAction {
        .init(id: script.id, name: script.name, icon: script.icon, content: script.content)
    }

    static func setEnabled(_ name: String, enabled: Bool, store: ScriptStore) {
        if let script = store.scripts.first(where: { $0.name == name }) {
            var updated = script; updated.isEnabled = enabled; store.updateScript(updated)
        } else if let entry = ScriptLibrary.libraryScript(named: name) {
            store.setLibraryScript(entry, isEnabled: enabled)
        }
    }

    @discardableResult
    static func addApplication(_ url: URL, store: ScriptStore) -> String? {
        guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url), bundle.executableURL != nil else {
            return L10n.text("请选择一个有效的 Mac 应用。", "Choose a valid Mac application.")
        }
        let normalized = url.resolvingSymlinksInPath().standardizedFileURL
        if let existing = store.scripts.first(where: { script in
            guard let app = applicationURL(for: script) else { return false }
            return app.resolvingSymlinksInPath().standardizedFileURL == normalized
        }) {
            var updated = existing; updated.isEnabled = true; store.updateScript(updated)
            return nil
        }
        let display = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        let action = ComposedAction(steps: [.init(op: "file.openWith", params: ["appPath": url.path])])
        store.addScript(Script(name: "用 \(display) 打开", type: .composed, content: action.encoded(),
                               icon: "app", appliesTo: .allItems, libraryCategory: ScriptStore.topCategoryKey))
        return nil
    }
}
