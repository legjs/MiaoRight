import Foundation
import MiaoRightShared

/// 官方 7zz 随 App 打包；只在独立暂存目录中处理，成功后才公布结果。
struct SevenZipArchive: Sendable {
    enum Format: String, CaseIterable {
        case sevenZip = "7z", zip, tarGzip = "tar.gz"

        init?(archive: URL) {
            let name = archive.lastPathComponent.lowercased()
            if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { self = .tarGzip }
            else if name.hasSuffix(".zip") { self = .zip }
            else if name.hasSuffix(".7z") { self = .sevenZip }
            else { return nil }
        }

        func extractedName(for archive: URL) -> String {
            let name = archive.lastPathComponent
            if self == .tarGzip && name.lowercased().hasSuffix(".tar.gz") { return String(name.dropLast(7)) }
            return archive.deletingPathExtension().lastPathComponent
        }
    }

    typealias PasswordProvider = (_ archiveName: String, _ retry: Bool) -> String?
    let executableURL: URL

    init(executableURL: URL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/7zz")) {
        self.executableURL = executableURL
    }

    func compress(_ urls: [URL], format: Format = .sevenZip, at destination: URL? = nil, password: String? = nil) throws -> URL {
        guard let first = urls.first else { throw failure(L10n.text("没有选中文件。", "No files selected.")) }
        let parent = first.deletingLastPathComponent().standardizedFileURL
        guard urls.allSatisfy({ $0.deletingLastPathComponent().standardizedFileURL == parent }) else {
            throw failure(L10n.text("请选择同一文件夹中的项目进行压缩。", "Select items from the same folder to compress."))
        }
        let secret = password.flatMap { $0.isEmpty ? nil : $0 }
        if let secret {
            try validatePassword(secret)
            guard format != .tarGzip else { throw failure(L10n.text("密码保护请选择 ZIP 或 7Z 格式。", "Choose ZIP or 7Z for password protection.")) }
            if format == .zip && !secret.unicodeScalars.allSatisfy({ $0.value < 128 }) {
                throw failure(L10n.text("ZIP 加密请使用英文、数字或符号密码；中文密码请选择 7Z。", "Use an ASCII password for ZIP encryption; choose 7Z for other characters."))
            }
        }
        let encryption = secret == nil ? [] : ["-p", format == .zip ? "-mem=AES256" : "-mhe=on"]
        let outputParent = destination?.deletingLastPathComponent() ?? parent
        let staging = try makeStagingDirectory(in: outputParent)
        defer { try? FileManager.default.removeItem(at: staging) }
        let archive = staging.appendingPathComponent("archive." + format.rawValue)
        // ./ 与 -spd 防止文件名中的 @、-、*、? 被解释成列表、选项或通配符。
        let inputNames = urls.map { "./" + $0.lastPathComponent }
        let container = format == .tarGzip ? "tar" : format.rawValue
        let intermediate = format == .tarGzip ? staging.appendingPathComponent("archive.tar") : archive
        // ZIP 显式使用 Deflate，保证 Finder、Windows 与 Office 的兼容性。
        let method = format == .zip ? ["-mm=Deflate"] : []
        try requireSuccess(run(["a", "-t" + container, "-snl", "-spd"] + method + encryption + quietArguments + ["--", intermediate.path] + inputNames, in: parent, password: secret), compressing: true)
        if format == .tarGzip {
            // TAR.GZ 必须先打包 TAR，再压缩单个 TAR；不能把多个文件直接送给 gzip。
            try requireSuccess(run(["a", "-tgzip"] + quietArguments + ["--", archive.path, intermediate.lastPathComponent], in: staging), compressing: true)
        }
        let name = urls.count == 1
            ? (format == .sevenZip ? first.lastPathComponent : first.deletingPathExtension().lastPathComponent)
            : L10n.text("归档", "Archive")
        let output = destination ?? NativeActionExecutor.uniqueDestinationURL(in: outputParent, preferredName: name, pathExtension: format.rawValue)
        // 显式目标同样不覆盖已有文件（例如新建 Office 文档时发生重名竞争）。
        try FileManager.default.moveItem(at: archive, to: output)
        FileOperationJournal.shared.recordOutputs([output])
        return output
    }

    func extract(_ archive: URL, format requestedFormat: Format? = nil, passwordProvider: PasswordProvider? = nil) throws -> URL {
        let input = try ArchiveInput(archive, format: requestedFormat)
        let archive = input.url
        let parent = archive.deletingLastPathComponent()
        let staging = try makeStagingDirectory(in: parent)
        defer { try? FileManager.default.removeItem(at: staging) }
        let contents = staging.appendingPathComponent("contents", isDirectory: true)
        if let stream = input.stream {
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: false)
            let streamFile = input.containsTar ? staging.appendingPathComponent("archive.tar")
                : contents.appendingPathComponent(input.extractedName.isEmpty ? "Archive" : input.extractedName)
            // 单文件压缩流写入受控路径，不采用压缩头中的文件名。
            try requireSuccess(run(["x", "-t" + stream, "-so"] + quietArguments + ["--", archive.path], in: parent, output: streamFile), compressing: false)
            if input.containsTar {
                try requireSuccess(run(["x", "-ttar", "-aou", "-snld0", "-o" + contents.path] + quietArguments + ["--", streamFile.path], in: parent), compressing: false)
            }
            return try publish(contents, archive: archive, name: input.extractedName)
        }
        var password: String?
        var attempt = 0
        while true {
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: false)
            // 同名归档条目自动换名；禁止危险链接，保留目录层级。
            let arguments = ["x", "-aou", "-snld0", "-o" + contents.path] + (input.type.map { ["-t" + $0] } ?? []) + quietArguments + ["--", archive.path]
            // 首次传空密码，避免 EOF 被 7zz 解释为中断；加密时能得到明确的密码错误。
            let result = try run(arguments, in: parent, password: password ?? "")
            if result.status == 0 {
                return try publish(contents, archive: archive, name: input.extractedName)
            }
            let message = result.message.lowercased()
            let needsPassword = ["wrong password", "password is incorrect", "enter password", "encrypted archive", "encrypted file"].contains { message.contains($0) }
            guard needsPassword else {
                throw extractionFailure(result.message)
            }
            guard attempt < 3, let passwordProvider else {
                throw failure(L10n.text("无法解压加密压缩包，请检查密码。", "Could not extract the encrypted archive. Check the password."))
            }
            guard let entered = passwordProvider(archive.lastPathComponent, attempt > 0) else {
                throw failure(L10n.text("已取消解压。", "Extraction cancelled."))
            }
            try validatePassword(entered)
            password = entered
            attempt += 1
            try FileManager.default.removeItem(at: contents)
        }
    }

    func extract(_ archives: [URL], format: Format? = nil, passwordProvider: PasswordProvider? = nil) throws -> [URL] {
        guard !archives.isEmpty else { throw failure(L10n.text("没有选中压缩包。", "No archives selected.")) }
        var destinations: [URL] = []
        var processed = Set<URL>()
        for archive in archives {
            do {
                let input = try ArchiveInput(archive, format: format)
                guard processed.insert(input.url.standardizedFileURL).inserted else { continue }
                destinations.append(try extract(archive, format: format, passwordProvider: passwordProvider))
            } catch {
                let completed = destinations.isEmpty ? "" : L10n.text("\n已完成：\n", "\nCompleted:\n") + destinations.map(\.path).joined(separator: "\n")
                throw failure(archive.lastPathComponent + ": " + error.localizedDescription + completed)
            }
        }
        return destinations
    }

    private var quietArguments: [String] { ["-y", "-bd", "-bso0", "-bsp0", "-bse1", "-sccUTF-8"] }
    private func failure(_ message: String) -> ScriptError { .executionFailed(message) }
    private func extractionFailure(_ detail: String) -> ScriptError {
        failure(L10n.text("解压失败，压缩包可能损坏或不可读取：", "Extraction failed. The archive may be damaged or unreadable: ") + detail)
    }

    private func requireSuccess(_ result: ProcessResult, compressing: Bool) throws {
        guard result.status == 0 else {
            if compressing { throw failure(L10n.text("压缩失败：", "Compression failed: ") + result.message) }
            throw extractionFailure(result.message)
        }
    }

    private func publish(_ contents: URL, archive: URL, name: String) throws -> URL {
        let destination = NativeActionExecutor.uniqueDestinationURL(
            in: archive.deletingLastPathComponent(), preferredName: name
        )
        try FileManager.default.moveItem(at: contents, to: destination)
        FileOperationJournal.shared.recordOutputs([destination])
        return destination
    }

    private func validatePassword(_ value: String) throws {
        guard value.utf8.count <= 1024, value.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }) else {
            throw failure(L10n.text("密码过长或包含控制字符。", "The password is too long or contains control characters."))
        }
    }

    private func makeStagingDirectory(in parent: URL) throws -> URL {
        let url = parent.appendingPathComponent(".miaoright-7z-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return url
    }

    private struct ProcessResult {
        let status: Int32
        let message: String
    }

    private func run(_ arguments: [String], in directory: URL, password: String? = nil, output: URL? = nil) throws -> ProcessResult {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw failure(L10n.text("App 内的压缩工具缺失或损坏，请重新安装妙右。", "The bundled archive tool is missing or damaged. Reinstall MiaoRight."))
        }
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("miaoright-7z-" + UUID().uuidString + ".log")
        guard FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw failure(L10n.text("无法创建压缩工具日志，请检查磁盘空间。", "Could not create an archive log. Check available disk space."))
        }
        defer { try? FileManager.default.removeItem(at: logURL) }
        let log = try FileHandle(forUpdating: logURL)
        defer { try? log.close() }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = directory
        // 写入文件避免大量错误输出塞满 Pipe 后卡住进程。
        var outputFile: FileHandle?
        if let output {
            guard FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw failure(L10n.text("无法创建解压文件，请检查磁盘空间。", "Could not create the extracted file. Check available disk space."))
            }
            outputFile = try FileHandle(forWritingTo: output)
        }
        defer { try? outputFile?.close() }
        process.standardOutput = outputFile ?? log
        process.standardError = log
        let input = Pipe()
        process.standardInput = password == nil ? FileHandle.nullDevice : input.fileHandleForReading
        if let password {
            // 密码只通过 stdin 传递，不写入命令行、磁盘或用户配置。
            try input.fileHandleForWriting.write(contentsOf: Data((password + "\n").utf8))
        }
        try input.fileHandleForWriting.close()
        try process.run()
        try input.fileHandleForReading.close()
        process.waitUntilExit()
        let end = try log.seekToEnd()
        try log.seek(toOffset: end > 16_384 ? end - 16_384 : 0)
        let data = try log.readToEnd() ?? Data()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return ProcessResult(status: process.terminationStatus, message: String(output.suffix(2_000)))
    }
}
