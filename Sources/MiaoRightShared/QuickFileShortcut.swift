import Foundation

/// 普通用户添加的目录/模板仍使用既有组合动作格式，保留跨进程与旧配置兼容。
public struct QuickFileShortcut: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case openFolder = "file.openFolder"
        case copy = "file.copy"
        case move = "file.move"
        case template = "file.fromTemplate"

        public var menuTitle: String {
            switch self {
            case .openFolder: L10n.text("常用文件夹", "Favorite Folders")
            case .copy: L10n.text("复制到", "Copy To")
            case .move: L10n.text("移动到", "Move To")
            case .template: L10n.text("从模板新建", "New from Template")
            }
        }
        public var icon: String {
            switch self {
            case .openFolder: "folder"
            case .copy: "doc.on.doc"
            case .move: "arrow.up.forward.square"
            case .template: "doc.badge.plus"
            }
        }

        public init?(menuTitle: String) {
            guard let match = Kind.allCases.first(where: { $0.menuTitle == menuTitle }) else { return nil }
            self = match
        }
    }

    public let kind: Kind
    public let targetPath: String
    public let title: String

    public init(kind: Kind, targetPath: String, title: String) {
        self.kind = kind; self.targetPath = targetPath; self.title = title
    }

    public init?(content: String) {
        guard let data = content.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["version"] as? Int == 1, let steps = json["steps"] as? [[String: Any]], steps.count == 1,
              let op = steps[0]["op"] as? String, let kind = Kind(rawValue: op),
              let params = steps[0]["params"] as? [String: String], params["miaorightShortcut"] == "1",
              let path = params[kind == .template ? "templatePath" : "folder"], path.hasPrefix("/"),
              let title = params["title"], !title.isEmpty else { return nil }
        self.init(kind: kind, targetPath: path, title: title)
    }

    public func encoded() -> String {
        let params = ["miaorightShortcut": "1", "title": title, kind == .template ? "templatePath" : "folder": targetPath]
        let json: [String: Any] = ["version": 1, "steps": [["op": kind.rawValue, "params": params]]]
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]), let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    public var isAvailable: Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: targetPath, isDirectory: &isDirectory) else { return false }
        return kind == .template || isDirectory.boolValue
    }
}
