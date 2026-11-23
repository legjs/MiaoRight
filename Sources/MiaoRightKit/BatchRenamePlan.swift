import Foundation
import MiaoRightShared

struct BatchRenameRule: Equatable, Sendable {
    enum Mode: String, CaseIterable, Identifiable {
        case replace, affixes, sequence, lowercase, uppercase, spaces
        var id: String { rawValue }
        var title: String {
            switch self {
            case .replace: L10n.text("替换文字", "Replace Text")
            case .affixes: L10n.text("添加前后缀", "Add Prefix and Suffix")
            case .sequence: L10n.text("编号", "Number Files")
            case .lowercase: L10n.text("转为小写", "Lowercase")
            case .uppercase: L10n.text("转为大写", "Uppercase")
            case .spaces: L10n.text("空格转下划线", "Spaces to Underscores")
            }
        }
    }
    var mode: Mode = .replace
    var search = ""
    var replacement = ""
    var prefix = ""
    var suffix = ""
    var baseName = ""
    var start = 1
    var digits = 3
}

struct BatchRenamePlan: Sendable {
    struct Row: Identifiable, Sendable {
        let source: URL
        let destination: URL
        let originalIdentity: String?
        var issue: String?
        var id: String { source.path }
        var changed: Bool { source.path != destination.path }
    }
    let rows: [Row]
    var canApply: Bool { !rows.isEmpty && rows.contains(where: \.changed) && rows.allSatisfy { $0.issue == nil } }

    init(urls: [URL], rule: BatchRenameRule) {
        let sourceKeys = Set(urls.map(FileOperationJournal.pathKey))
        var rows: [Row] = []
        for (index, url) in urls.enumerated() {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            let folder = values?.isDirectory == true && values?.isPackage != true
            let ext = folder ? "" : url.pathExtension
            let stem = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
            var name = stem
            var issue: String?
            switch rule.mode {
            case .replace:
                if rule.search.isEmpty { issue = L10n.text("请输入要替换的文字。", "Enter the text to replace.") }
                else { name = stem.replacingOccurrences(of: rule.search, with: rule.replacement) }
            case .affixes: name = rule.prefix + stem + rule.suffix
            case .sequence:
                let (number, overflow) = rule.start.addingReportingOverflow(index)
                if overflow || number < 0 || number > 99_999_999 || !(1...8).contains(rule.digits) { issue = L10n.text("编号范围或位数无效。", "The numbering range or width is invalid.") }
                else { name = (rule.baseName.isEmpty ? stem : rule.baseName) + "-" + String(format: "%0*d", rule.digits, number) }
            case .lowercase: name = stem.lowercased()
            case .uppercase: name = stem.uppercased()
            case .spaces: name = stem.replacingOccurrences(of: " ", with: "_")
            }
            if !ext.isEmpty { name += "." + ext }
            if name.isEmpty || name == "." || name == ".." || name.contains("/") || name.contains("\0") || name.utf8.count > 255 {
                issue = L10n.text("文件名无效或过长。", "The file name is invalid or too long.")
            }
            let destination = url.deletingLastPathComponent().appendingPathComponent(name)
            let exists = (try? FileManager.default.attributesOfItem(atPath: destination.path)) != nil
            if exists && !sourceKeys.contains(FileOperationJournal.pathKey(destination)) {
                issue = L10n.text("已存在同名文件。", "An item with this name already exists.")
            }
            let identity = try? Self.identity(url)
            if identity == nil { issue = L10n.text("文件已不可用。", "The file is unavailable.") }
            rows.append(Row(source: url, destination: destination, originalIdentity: identity, issue: issue))
        }
        let duplicates = Dictionary(grouping: rows.indices, by: { FileOperationJournal.pathKey(rows[$0].destination) }).values.filter { $0.count > 1 }.flatMap { $0 }
        for index in duplicates { rows[index].issue = L10n.text("多个项目将使用同一名称。", "Multiple items would have the same name.") }
        self.rows = rows
    }

    @discardableResult
    func apply(journal: FileOperationJournal = .shared) throws -> [URL] {
        guard canApply else { throw ScriptError.executionFailed(L10n.text("请先修复预览中的问题。", "Resolve the issues in the preview first.")) }
        for row in rows {
            guard try Self.identity(row.source) == row.originalIdentity else {
                throw ScriptError.executionFailed(L10n.text("文件在预览后已发生变化，请重新预览。", "Files changed after the preview. Refresh the preview first."))
            }
        }
        let moves = rows.filter(\.changed).map { FileMove(source: $0.source, destination: $0.destination) }
        _ = try journal.perform(moves, title: L10n.text("重命名", "Rename"))
        return rows.map(\.destination)
    }

    private static func identity(_ url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return [.systemNumber, .systemFileNumber, .size, .modificationDate].map { String(describing: attributes[$0] ?? "") }.joined(separator: "|")
    }
}
