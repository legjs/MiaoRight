import Foundation

/// 主窗口预览和 Finder 共用的菜单计划。输入只包含当前选择下可用的动作。
public struct QuickMenuAction: Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var icon: String
    public var content: String
    public init(id: UUID, name: String, icon: String, content: String = "") {
        self.id = id; self.name = name; self.icon = icon; self.content = content
    }
}

public struct QuickMenuSection: Equatable, Sendable {
    public var title: String?
    public var icon: String
    public var actions: [QuickMenuAction]
}

public enum QuickMenuPlan {
    public static let applicationBundleIDs: [String: [String]] = [
        "在终端中打开": ["com.apple.Terminal"], "在 iTerm2 中打开": ["com.googlecode.iterm2"],
        "在 Warp 中打开": ["dev.warp.Warp-Stable"], "在 VS Code 中打开": ["com.microsoft.VSCode"],
        "在 Cursor 中打开": ["com.todesktop.230313mzl4w4u92"], "在 Sublime Text 中打开": ["com.sublimetext.4", "com.sublimetext.3"],
        "在 Typora 中打开": ["abnerworks.Typora"], "在 Obsidian 中打开": ["md.obsidian"],
        "在 IDEA 中打开": ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"],
        "在 PyCharm 中打开": ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"],
        "在 CLion 中打开": ["com.jetbrains.CLion"], "在 WebStorm 中打开": ["com.jetbrains.WebStorm"],
        "在 GoLand 中打开": ["com.jetbrains.goland"], "在 DataGrip 中打开": ["com.jetbrains.datagrip"],
        "在 Android Studio 中打开": ["com.google.android.studio"], "用 Xcode 打开": ["com.apple.dt.Xcode"]
    ]

    public static func isAvailable(_ action: QuickMenuAction, resolveBundleID: (String) -> URL?) -> Bool {
        if let shortcut = QuickFileShortcut(content: action.content) { return shortcut.isAvailable }
        if action.name == VaultConfig.actionName { return VaultConfig.isAvailable }
        if let path = applicationPath(in: action.content) {
            let url = URL(fileURLWithPath: path)
            return FileManager.default.fileExists(atPath: path) && Bundle(url: url)?.executableURL != nil
        }
        if let ids = applicationBundleIDs[action.name] {
            return ids.contains { resolveBundleID($0) != nil }
        }
        return true
    }
    public static let terminalNames = ["在终端中打开", "在 iTerm2 中打开", "在 Warp 中打开"]
    public static let applicationNames = [
        "在 VS Code 中打开", "在 Cursor 中打开", "在 Sublime Text 中打开", "在 Typora 中打开",
        "在 Obsidian 中打开", "在 IDEA 中打开", "在 PyCharm 中打开", "在 CLion 中打开",
        "在 WebStorm 中打开", "在 GoLand 中打开", "在 DataGrip 中打开", "在 Android Studio 中打开", "用 Xcode 打开"
    ]

    /// 只把单步打开应用归入常用应用,不改变旧多步组合动作的语义。
    public static func applicationPath(in content: String) -> String? {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let steps = json["steps"] as? [[String: Any]], steps.count == 1,
              steps[0]["op"] as? String == "file.openWith",
              let params = steps[0]["params"] as? [String: String],
              let path = params["appPath"], !path.isEmpty else { return nil }
        return path
    }

    public static func isApplication(name: String, content: String) -> Bool {
        applicationNames.contains(name) || applicationPath(in: content) != nil
    }

    public static func applicationTitle(_ action: QuickMenuAction) -> String {
        if let path = applicationPath(in: action.content) {
            return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
        if action.name == "用 Xcode 打开" { return "Xcode" }
        return action.name.replacingOccurrences(of: "在 ", with: "").replacingOccurrences(of: " 中打开", with: "")
    }

    public static func title(_ action: QuickMenuAction) -> String {
        if let shortcut = QuickFileShortcut(content: action.content) { return shortcut.title }
        if action.name == "复制路径" { return L10n.text("复制文件路径", "Copy File Path") }
        if action.name == ActionID.paste { return L10n.text("粘贴到此处", "Paste Here") }
        return ActionNames.name(action.name)
    }

    public static func sections(for actions: [QuickMenuAction]) -> [QuickMenuSection] {
        var result: [QuickMenuSection] = []
        var consumed = Set<UUID>()
        func append(_ matches: [QuickMenuAction], title: String? = nil, icon: String) {
            guard !matches.isEmpty else { return }
            result.append(.init(title: title, icon: icon, actions: matches))
            consumed.formUnion(matches.map(\.id))
        }
        append(actions.filter { $0.name == "复制路径" }, icon: "link")
        append(actions.filter { isApplication(name: $0.name, content: $0.content) },
               title: L10n.text("用应用打开", "Open with App"), icon: "app")
        let terminals = terminalNames.flatMap { name in actions.filter { $0.name == name } }
        append(terminals, title: terminals.count > 1 ? L10n.text("在终端打开", "Open in Terminal") : nil, icon: "terminal")
        for name in [ActionID.cut, ActionID.paste] {
            append(actions.filter { $0.name == name }, icon: name == ActionID.cut ? "scissors" : "doc.on.clipboard")
        }
        for kind in QuickFileShortcut.Kind.allCases {
            append(actions.filter { QuickFileShortcut(content: $0.content)?.kind == kind }, title: kind.menuTitle, icon: kind.icon)
        }
        append(actions.filter { !consumed.contains($0.id) }, title: L10n.text("更多操作", "More Actions"), icon: "ellipsis.circle")
        return result
    }
}
