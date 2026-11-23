import AppKit
import Foundation
import MiaoRightShared

// MARK: - Shell

/// 极简进程执行(macOS 自带工具;sips/osascript)
enum Shell {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) async throws -> String {
        let (code, out) = try await runRaw(executable, arguments)
        guard code == 0 else { throw PipelineError.runtime("命令失败(exit \(code)):\(out)") }
        return out
    }

    static func runRaw(_ executable: String, _ arguments: [String]) async throws -> (Int, String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            throw PipelineError.runtime("无法运行 \(executable): \(error.localizedDescription)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        return (Int(process.terminationStatus), out.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - 文件操作(冲突自动加序号,绝不覆盖已有文件)

enum FileOps {
    /// 目标已存在时生成「名称 2」「名称 3」…
    static func uniquedDestination(for url: URL, in folder: URL) -> URL {
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var candidate = folder.appendingPathComponent(url.lastPathComponent)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let suffix = ext.isEmpty ? "\(name) \(index)" : "\(name) \(index).\(ext)"
            candidate = folder.appendingPathComponent(suffix)
            index += 1
        }
        return candidate
    }

    static func copy(_ urls: [URL], to folder: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var result: [URL] = []
        for url in urls {
            let dest = uniquedDestination(for: url, in: folder)
            try FileManager.default.copyItem(at: url, to: dest)
            result.append(dest)
            FileOperationJournal.shared.recordOutputs([dest])
        }
        return result
    }

    static func move(_ urls: [URL], to folder: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var result: [URL] = []
        var moves: [FileMove] = []
        var reserved = Set<String>()
        for url in urls {
            if url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == folder.resolvingSymlinksInPath().standardizedFileURL {
                result.append(url); continue
            }
            var dest = uniquedDestination(for: url, in: folder)
            var suffix = 2
            while reserved.contains(FileOperationJournal.pathKey(dest)) {
                let name = url.deletingPathExtension().lastPathComponent + "-\(suffix)"
                dest = NativeActionExecutor.uniqueDestinationURL(in: folder, preferredName: name, pathExtension: url.pathExtension)
                suffix += 1
            }
            reserved.insert(FileOperationJournal.pathKey(dest))
            moves.append(FileMove(source: url, destination: dest))
            result.append(dest)
        }
        _ = try FileOperationJournal.shared.perform(moves, title: L10n.text("移动", "Move"))
        return result
    }

    static func duplicate(_ urls: [URL]) throws -> [URL] {
        var result: [URL] = []
        for url in urls {
            let folder = url.deletingLastPathComponent()
            let name = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            let copyName = ext.isEmpty ? "\(name) 副本" : "\(name) 副本.\(ext)"
            let dest = uniquedDestination(for: URL(fileURLWithPath: copyName), in: folder)
            try FileManager.default.copyItem(at: url, to: dest)
            result.append(dest)
        }
        return result
    }

    static func rename(_ urls: [URL], mode: String) throws -> [URL] {
        var result: [URL] = []
        var moves: [FileMove] = []
        for (i, url) in urls.enumerated() {
            let folder = url.deletingLastPathComponent()
            var name = url.deletingPathExtension().lastPathComponent
            switch mode {
            case "lowercase": name = name.lowercased()
            case "uppercase": name = name.uppercased()
            case "spaces": name = name.replacingOccurrences(of: " ", with: "_")
            case "sequence": name = String(format: "%03d-%@", i + 1, name)
            default: break
            }
            let newName = url.pathExtension.isEmpty ? name : "\(name).\(url.pathExtension)"
            let dest = folder.appendingPathComponent(newName)
            moves.append(FileMove(source: url, destination: dest))
            result.append(dest)
        }
        _ = try FileOperationJournal.shared.perform(moves, title: L10n.text("重命名", "Rename"))
        return result
    }

    /// 新建文件/文件夹的落点:最前面的 Finder 窗口,取不到回退桌面
    static func finderTargetFolder() -> URL {
        if let url = AppleScriptFinder.frontmostFolder() { return url }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    static func createFile(name: String) throws -> URL {
        let folder = finderTargetFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = uniquedDestination(for: URL(fileURLWithPath: name), in: folder)
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        return dest
    }

    static func createFolder(name: String) throws -> URL {
        let folder = finderTargetFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = uniquedDestination(for: URL(fileURLWithPath: name), in: folder)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        return dest
    }

    /// 与右键动作共用随包提供的压缩后端。
    static func zip(_ urls: [URL], archiver: SevenZipArchive = SevenZipArchive()) async throws -> URL {
        try archiver.compress(urls, format: .zip)
    }

    static func unzip(_ urls: [URL], archiver: SevenZipArchive = SevenZipArchive()) async throws -> [URL] {
        var result: [URL] = []
        let destinations = try archiver.extract(urls, passwordProvider: NativeActionExecutor.requestArchivePassword)
        for destination in destinations {
            // 保留旧组合动作的产物契约：传递解出的子项，而不是包裹文件夹。
            result.append(contentsOf: try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent })
        }
        return result
    }
}

/// 取最前面 Finder 窗口显示的文件夹(无窗口返回 nil)
enum AppleScriptFinder {
    static func frontmostFolder() -> URL? {
        let script = """
        tell application "Finder"
            if (count of Finder windows) > 0 then
                return POSIX path of (target of front Finder window as alias)
            end if
        end tell
        """
        var error: NSDictionary?
        let output = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue
        guard let path = output?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty, path.hasPrefix("/")
        else { return nil }
        return URL(fileURLWithPath: path)
    }
}

// MARK: - 图片操作(全部「只写新文件,不动原件」;sips 为 macOS 标配)

enum ImageOps {
    static func convert(_ urls: [URL], format: String) throws -> [URL] {
        let ext = format == "jpeg" ? "jpg" : format
        var result: [URL] = []
        for url in urls {
            let folder = url.deletingLastPathComponent()
            let name = url.deletingPathExtension().lastPathComponent
            let dest = FileOps.uniquedDestination(for: URL(fileURLWithPath: "\(name).\(ext)"), in: folder)
            try ShellSync.run("/usr/bin/sips", ["-s", "format", format, url.path, "--out", dest.path])
            result.append(dest)
        }
        return result
    }

    static func resize(_ urls: [URL], width: Int) throws -> [URL] {
        var result: [URL] = []
        for url in urls {
            let folder = url.deletingLastPathComponent()
            let name = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            let dest = FileOps.uniquedDestination(for: URL(fileURLWithPath: "\(name)-\(width).\(ext)"), in: folder)
            try ShellSync.run("/usr/bin/sips", ["--resampleWidth", String(width), url.path, "--out", dest.path])
            result.append(dest)
        }
        return result
    }

    static func rotate(_ urls: [URL], degrees: String) throws -> [URL] {
        var result: [URL] = []
        for url in urls {
            let folder = url.deletingLastPathComponent()
            let name = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            let dest = FileOps.uniquedDestination(for: URL(fileURLWithPath: "\(name)-r\(degrees).\(ext)"), in: folder)
            try ShellSync.run("/usr/bin/sips", ["-r", degrees, url.path, "--out", dest.path])
            result.append(dest)
        }
        return result
    }

    static func setWallpaper(_ url: URL) async throws {
        let posix = url.path.escapedForAppleScript
        _ = try await Shell.run("/usr/bin/osascript", ["-e",
            "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"\(posix)\""])
    }
}

/// 同步版进程执行(图片这类小步骤在引擎后台上下文同步等待,量小无碍)
enum ShellSync {
    static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        _ = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PipelineError.runtime("\(executable) 执行失败(exit \(process.terminationStatus))")
        }
    }
}
