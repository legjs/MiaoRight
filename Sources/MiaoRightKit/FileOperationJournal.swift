import CryptoKit
import Foundation
import MiaoRightShared

enum FileTaskContext {
    @TaskLocal static var executionID: UUID?
}

struct FileMove: Equatable, Sendable {
    let source: URL
    let destination: URL
}

/// 只保存本次 App 会话中的可撤销移动，绝不通过删除现有文件来完成撤销。
final class FileOperationJournal: @unchecked Sendable {
    static let shared = FileOperationJournal()
    struct Change: Sendable {
        let move: FileMove
        let fingerprint: String
    }
    struct Receipt: Identifiable, Sendable {
        let id: UUID
        let executionID: UUID?
        let title: String
        var changes: [Change]
        var localizedTitle: String {
            switch title {
            case "移动", "Move": L10n.text("移动", "Move")
            case "重命名", "Rename": L10n.text("重命名", "Rename")
            default: title
            }
        }
    }
    struct Summary: Sendable {
        let outputPaths: [String]
        let undoID: UUID?
    }
    private let lock = NSRecursiveLock()
    private var history: [Receipt] = []
    private var outputs: [UUID: [String]] = [:]
    private let moveItem: (URL, URL) throws -> Void

    init(moveItem: @escaping (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }) {
        self.moveItem = moveItem
    }

    func receipt(_ id: UUID) -> Receipt? { lock.withLock { history.first { $0.id == id } } }
    func recordOutputs(_ urls: [URL]) {
        guard let executionID = FileTaskContext.executionID else { return }
        lock.withLock {
            outputs[executionID, default: []].append(contentsOf: urls.map(\.path))
            if outputs.count > 40 { for key in Array(outputs.keys).prefix(outputs.count - 40) where key != executionID { outputs.removeValue(forKey: key) } }
        }
    }
    func summary(for executionID: UUID) -> Summary {
        lock.withLock {
            var seen = Set<String>()
            let paths = (outputs[executionID] ?? []).filter { FileManager.default.fileExists(atPath: $0) && seen.insert($0).inserted }
            return Summary(outputPaths: paths, undoID: history.last { $0.executionID == executionID }?.id)
        }
    }

    @discardableResult
    func perform(_ moves: [FileMove], title: String) throws -> [URL] {
        try lock.withLock {
            let changes = moves.filter { $0.source.path != $0.destination.path }
            guard !changes.isEmpty else { return moves.map(\.destination) }
            try validate(changes)
            try relocate(changes)
            recordCompleted(changes, title: title)
            return moves.map(\.destination)
        }
    }

    /// 原有剪切粘贴保留部分完成语义：逐项成功后记录，错误时仍可撤销已完成项目。
    func recordCompleted(_ moves: [FileMove], title: String) {
        lock.withLock {
            let changes = moves.compactMap { move -> Change? in
                guard let fingerprint = try? Self.fingerprint(move.destination) else { return nil }
                return Change(move: move, fingerprint: fingerprint)
            }
            recordOutputs(moves.map(\.destination))
            guard !changes.isEmpty, changes.count == moves.count else {
                if let id = FileTaskContext.executionID { history.removeAll { $0.executionID == id && $0.title == title } }
                return
            }
            let executionID = FileTaskContext.executionID
            if let executionID, let last = history.last, last.executionID == executionID, last.title == title,
               !changes.contains(where: { change in last.changes.contains { Self.pathKey($0.move.destination) == Self.pathKey(change.move.source) } }) {
                history[history.count - 1].changes.append(contentsOf: changes)
            } else {
                history.append(Receipt(id: UUID(), executionID: executionID, title: title, changes: changes))
            }
            if history.count > 20 { history.removeFirst(history.count - 20) }
        }
    }

    @discardableResult
    func undo(_ id: UUID) throws -> [URL] {
        try lock.withLock {
            guard let receipt = history.first(where: { $0.id == id }) else {
                throw error(L10n.text("这次操作已无法撤销。", "This operation can no longer be undone."))
            }
            // 先检查整个批次，再移动任何文件。目录签名同时覆盖子项元数据。
            for change in receipt.changes {
                guard try Self.fingerprint(change.move.destination) == change.fingerprint else {
                    throw error(L10n.text("文件已被修改，无法安全撤销：\(change.move.destination.lastPathComponent)", "The file has changed and cannot be safely undone: \(change.move.destination.lastPathComponent)"))
                }
            }
            let inverse = receipt.changes.map { FileMove(source: $0.move.destination, destination: $0.move.source) }
            try validate(inverse)
            try relocate(inverse)
            history.removeAll { $0.id == id }
            return inverse.map(\.destination)
        }
    }

    private func validate(_ moves: [FileMove]) throws {
        let sources = Set(moves.map { Self.pathKey($0.source) })
        var targets = Set<String>()
        guard sources.count == moves.count else { throw error(L10n.text("选中项目包含重复文件。", "The selection contains duplicate files.")) }
        for move in moves {
            _ = try FileManager.default.attributesOfItem(atPath: move.source.path)
            guard targets.insert(Self.pathKey(move.destination)).inserted else {
                throw error(L10n.text("多个文件将使用同一个名称。", "Multiple files would use the same name."))
            }
            let destinationExists = (try? FileManager.default.attributesOfItem(atPath: move.destination.path)) != nil
            if destinationExists && !sources.contains(Self.pathKey(move.destination)) {
                throw error(L10n.text("目标位置已被占用，未覆盖任何文件：\(move.destination.path)", "The destination is occupied. No files were overwritten: \(move.destination.path)"))
            }
            let parent = try move.destination.deletingLastPathComponent().resourceValues(forKeys: [.isDirectoryKey])
            guard parent.isDirectory == true else { throw error(L10n.text("目标文件夹已不可用。", "The destination folder is unavailable.")) }
        }
        for move in moves {
            let path = move.source.standardizedFileURL.path + "/"
            guard !moves.contains(where: { $0.source.standardizedFileURL.path.hasPrefix(path) }) else {
                throw error(L10n.text("请勿同时操作文件夹及其内部文件。", "Do not select a folder together with files inside it."))
            }
            guard !moves.contains(where: { $0.destination.standardizedFileURL.path.hasPrefix(path) }) else {
                throw error(L10n.text("不能把项目移动到选中文件夹内部。", "An item cannot be moved inside a selected folder."))
            }
        }
    }

    /// 两阶段重定位支持交换名称与仅改变大小写；失败时保留所有原始数据并尝试回滚。
    private func relocate(_ moves: [FileMove]) throws {
        var current = moves.map(\.source)
        do {
            for index in moves.indices {
                let staged = temporarySibling(of: moves[index].source)
                try moveItem(current[index], staged)
                current[index] = staged
            }
            for index in moves.indices {
                try moveItem(current[index], moves[index].destination)
                current[index] = moves[index].destination
            }
        } catch {
            var recovery: [String] = []
            // 先移开已完成的目标，避免名称交换时回滚互相占位。
            for index in moves.indices where current[index].path != moves[index].source.path {
                let staged = temporarySibling(of: moves[index].source)
                do { try moveItem(current[index], staged); current[index] = staged }
                catch { recovery.append(current[index].path) }
            }
            for index in moves.indices where current[index].path != moves[index].source.path {
                do {
                    guard (try? FileManager.default.attributesOfItem(atPath: moves[index].source.path)) == nil else {
                        recovery.append(current[index].path); continue
                    }
                    try moveItem(current[index], moves[index].source)
                    current[index] = moves[index].source
                } catch { recovery.append(current[index].path) }
            }
            let locations = recovery.isEmpty ? "" : L10n.text("\n需要手动恢复的文件保留在：\n", "\nFiles requiring manual recovery remain at:\n") + Set(recovery).sorted().joined(separator: "\n")
            throw self.error(L10n.text("文件操作未完成：", "The file operation did not complete: ") + error.localizedDescription + locations)
        }
    }

    private func temporarySibling(of url: URL) -> URL { url.deletingLastPathComponent().appendingPathComponent(".miaoright-move-" + UUID().uuidString) }
    private func error(_ message: String) -> ScriptError { .executionFailed(message) }

    static func pathKey(_ url: URL) -> String {
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
        let sensitive = (try? parent.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames) ?? false
        let value = parent.appendingPathComponent(url.lastPathComponent).standardizedFileURL.path.precomposedStringWithCanonicalMapping
        return sensitive ? value : value.lowercased()
    }

    static func fingerprint(_ url: URL) throws -> String {
        var descriptions: [String] = []
        func append(_ item: URL, relative: String) throws {
            let attributes = try FileManager.default.attributesOfItem(atPath: item.path)
            let keys: [FileAttributeKey] = [.type, .systemNumber, .systemFileNumber, .size, .modificationDate, .posixPermissions]
            let value = keys.map { key -> String in
                if let date = attributes[key] as? Date { return String(date.timeIntervalSince1970) }
                return String(describing: attributes[key] ?? "")
            }.joined(separator: "|")
            let link = attributes[.type] as? FileAttributeType == .typeSymbolicLink ? try FileManager.default.destinationOfSymbolicLink(atPath: item.path) : ""
            descriptions.append(relative + "|" + value + "|" + link)
        }
        try append(url, relative: "")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if attributes[.type] as? FileAttributeType == .typeDirectory {
            var traversalError: Error?
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [], errorHandler: { _, error in traversalError = error; return false }) else {
                throw CocoaError(.fileReadUnknown)
            }
            for case let child as URL in enumerator { try append(child, relative: String(child.path.dropFirst(url.path.count))) }
            if let traversalError { throw traversalError }
        }
        return SHA256.hash(data: Data(descriptions.sorted().joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
