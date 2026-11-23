import Foundation
import MiaoRightShared
import UniformTypeIdentifiers

enum ClipboardExport: Sendable {
    case document(name: String, type: UTType, data: Data)
    case files([URL])

    init(payload: ClipboardPayload) throws {
        switch payload {
        case let .text(text):
            self = .document(name: L10n.text("剪贴板文字", "Clipboard Text"), type: .plainText, data: Data(text.utf8))
        case let .image(data):
            self = .document(name: L10n.text("剪贴板图片", "Clipboard Image"), type: .png,
                             data: try NativeActionExecutor.clipboardImagePNG(data))
        case let .files(urls):
            guard !urls.isEmpty else {
                throw ScriptError.executionFailed(L10n.text("这条记录中没有文件。", "There are no files in this record."))
            }
            self = .files(urls)
        }
    }

    func write(to destination: URL) throws {
        switch self {
        case let .document(_, _, data):
            try data.write(to: destination, options: .atomic)
        case let .files(urls):
            let folder = destination.resolvingSymlinksInPath().standardizedFileURL
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                throw ScriptError.executionFailed(L10n.text("目标文件夹已不可用。", "The destination folder is unavailable."))
            }
            let targetPath = FileOperationJournal.pathKey(folder)
            for url in urls {
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
                    throw ScriptError.executionFailed(L10n.text("无法读取原文件“\(url.lastPathComponent)”。", "Could not access the original item “\(url.lastPathComponent)”."))
                }
                if attributes[.type] as? FileAttributeType == .typeDirectory {
                    let sourcePath = FileOperationJournal.pathKey(url)
                    guard targetPath != sourcePath, !targetPath.hasPrefix(sourcePath == "/" ? "/" : sourcePath + "/") else {
                        throw ScriptError.executionFailed(L10n.text("请选择原文件夹之外的位置。", "Choose a location outside the original folder."))
                    }
                }
            }
            _ = try FileOps.copy(urls, to: folder)
        }
    }
}
