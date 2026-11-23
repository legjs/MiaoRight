import Foundation
import MiaoRightShared

struct ArchiveInput {
    static let menuExtensions = ["zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "001", "r00", "z01"]
    let url: URL
    let type: String?
    let stream: String?
    let containsTar: Bool
    let extractedName: String

    init(_ selected: URL, format: SevenZipArchive.Format? = nil) throws {
        let selectedName = selected.lastPathComponent
        var url = selected
        var split = false
        var splitName: String?
        func match(_ expression: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: expression, options: .caseInsensitive),
                  let result = regex.firstMatch(in: selectedName, range: NSRange(selectedName.startIndex..., in: selectedName)) else { return nil }
            return (0..<result.numberOfRanges).compactMap { Range(result.range(at: $0), in: selectedName).map { String(selectedName[$0]) } }
        }
        if let parts = match(#"^(.+\.(?:7z|zip))\.(\d{3})$"#) {
            url = selected.deletingLastPathComponent().appendingPathComponent(parts[1] + ".001")
            splitName = URL(fileURLWithPath: parts[1]).deletingPathExtension().lastPathComponent
            split = true
        } else if let parts = match(#"^(.+)(\.part)(\d+)(\.rar)$"#) {
            let firstNumber = String(repeating: "0", count: max(0, parts[3].count - 1)) + "1"
            url = selected.deletingLastPathComponent().appendingPathComponent(parts[1] + parts[2] + firstNumber + parts[4])
            splitName = parts[1]; split = true
        } else if let parts = match(#"^(.+)\.r\d{2}$"#) {
            url = selected.deletingLastPathComponent().appendingPathComponent(parts[1] + ".rar")
            splitName = parts[1]; split = true
        } else if let parts = match(#"^(.+)\.z\d{2}$"#) {
            url = selected.deletingLastPathComponent().appendingPathComponent(parts[1] + ".zip")
            splitName = parts[1]; split = true
        }
        if split && !FileManager.default.fileExists(atPath: url.path) {
            let candidates = (try? FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil))?.filter { $0.lastPathComponent.lowercased() == url.lastPathComponent.lowercased() } ?? []
            if candidates.count == 1 { url = candidates[0] }
            else { throw ScriptError.executionFailed(L10n.text("缺少首个分卷：\(url.lastPathComponent)。请把全部分卷放在同一文件夹。", "Missing first volume: \(url.lastPathComponent). Keep all volumes in the same folder.")) }
        }
        self.url = url
        if split {
            type = nil; stream = nil; containsTar = false; extractedName = splitName ?? "Archive"
            return
        }
        let name = url.lastPathComponent
        let lower = name.lowercased()
        let tarStreams: [(String, String)] = [(".tar.gz", "gzip"), (".tgz", "gzip"), (".tar.xz", "xz"), (".txz", "xz"), (".tar.bz2", "bzip2"), (".tbz2", "bzip2"), (".tbz", "bzip2")]
        if format == .tarGzip || (format == nil && tarStreams.contains { lower.hasSuffix($0.0) }) {
            let suffix = tarStreams.first { lower.hasSuffix($0.0) }
            type = "tar"; stream = format == .tarGzip ? "gzip" : suffix!.1; containsTar = true
            extractedName = suffix.map { String(name.dropLast($0.0.count)) } ?? url.deletingPathExtension().lastPathComponent
        } else if let format {
            type = format.rawValue; stream = nil; containsTar = false; extractedName = url.deletingPathExtension().lastPathComponent
        } else if let streamType = ["gz": "gzip", "xz": "xz", "bz2": "bzip2"][url.pathExtension.lowercased()] {
            type = nil; stream = streamType; containsTar = false; extractedName = url.deletingPathExtension().lastPathComponent
        } else if ["zip", "7z", "rar", "tar"].contains(url.pathExtension.lowercased()) {
            type = url.pathExtension.lowercased(); stream = nil; containsTar = false; extractedName = url.deletingPathExtension().lastPathComponent
        } else {
            throw ScriptError.executionFailed(L10n.text("不支持此压缩包类型，请选择 ZIP、7Z、RAR、TAR、GZ、BZ2 或 XZ。", "Choose a ZIP, 7Z, RAR, TAR, GZ, BZ2 or XZ archive."))
        }
    }
}
