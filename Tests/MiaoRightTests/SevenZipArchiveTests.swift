import Foundation
import XCTest
@testable import MiaoRightKit

final class SevenZipArchiveTests: XCTestCase {
    private var executable: URL { ArchiveTestTool.executableURL }
    private var archiver: SevenZipArchive { SevenZipArchive(executableURL: executable) }

    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoRight-7Z-Tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func fixtureCommand(_ arguments: [String], in directory: URL, executableURL: URL? = nil) throws {
        let process = Process()
        process.executableURL = executableURL ?? executable
        process.currentDirectoryURL = directory
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "Fixture creation failed")
    }

    func testRoundTripPreservesNestedFilesAndLiteralNames() throws {
        let root = try directory()
        let folder = root.appendingPathComponent("中文文件夹", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let nested = folder.appendingPathComponent("照片与文字.txt")
        let bytes = Data((0..<200_000).map { UInt8($0 % 251) })
        try bytes.write(to: nested)
        let names = ["@filelist", "-mx=0", "[draft]*?.txt", "空 格'\"$文件.txt"]
        let files = names.map { root.appendingPathComponent($0) }
        for file in files { try Data(file.lastPathComponent.utf8).write(to: file) }
        try Data("Not selected".utf8).write(to: root.appendingPathComponent("unselected.txt"))

        for format in SevenZipArchive.Format.allCases {
            let archive = try archiver.compress([folder] + files, format: format)
            let output = try archiver.extract(archive)
            XCTAssertEqual(output.deletingLastPathComponent(), root)
            XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("中文文件夹/照片与文字.txt")), bytes)
            for file in files {
                XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent(file.lastPathComponent)), try Data(contentsOf: file))
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("unselected.txt").path))
        }
        XCTAssertEqual(try Data(contentsOf: nested), bytes)
    }

    func testExistingArchivesAndFoldersAreNeverOverwritten() throws {
        let root = try directory()
        let file = root.appendingPathComponent("记录.txt")
        try Data("Original".utf8).write(to: file)
        for format in SevenZipArchive.Format.allCases {
            let first = try archiver.compress([file], format: format)
            let originalArchive = try Data(contentsOf: first)
            let second = try archiver.compress([file], format: format)
            XCTAssertNotEqual(first, second)
            XCTAssertEqual(try Data(contentsOf: first), originalArchive)
            let firstOutput = try archiver.extract(first)
            let marker = firstOutput.appendingPathComponent("keep.txt")
            try Data("Keep".utf8).write(to: marker)
            let secondOutput = try archiver.extract(first)
            XCTAssertNotEqual(firstOutput, secondOutput)
            XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "Keep")
            XCTAssertEqual(try String(contentsOf: secondOutput.appendingPathComponent("记录.txt"), encoding: .utf8), "Original")
        }
    }

    func testFailuresRemovePartialResultsAndPreserveInputs() throws {
        let root = try directory()
        let bytes = Data("This is not an archive".utf8)
        for format in SevenZipArchive.Format.allCases {
            let broken = root.appendingPathComponent("broken." + format.rawValue)
            try bytes.write(to: broken)
            XCTAssertThrowsError(try archiver.extract(broken))
            XCTAssertThrowsError(try archiver.compress([root.appendingPathComponent("missing.txt")], format: format))
            XCTAssertEqual(try Data(contentsOf: broken), bytes)
            let missingTool = SevenZipArchive(executableURL: root.appendingPathComponent("missing-tool"))
            XCTAssertThrowsError(try missingTool.compress([broken], format: format))
        }
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), Set(SevenZipArchive.Format.allCases.map { "broken." + $0.rawValue }))
    }

    func testEncryptedArchivesCanRetryWithPasswordOverStdin() throws {
        let root = try directory()
        let file = root.appendingPathComponent("secret.txt")
        try Data("Fixture secret".utf8).write(to: file)
        for (name, type, method) in [("headers.7z", "7z", "-mhe=on"), ("data.7z", "7z", "-mhe=off"), ("aes.zip", "zip", "-mem=AES256"), ("legacy.zip", "zip", "-mem=ZipCrypto")] {
            let archive = root.appendingPathComponent(name)
            let password = type == "7z" ? "fixture-password-中文" : "fixture-password"
            try fixtureCommand(["a", "-t" + type, "-p" + password, method, archive.path, "secret.txt"], in: root)
            var prompts: [Bool] = []
            let output = try archiver.extract(archive, passwordProvider: { name, retry in
                XCTAssertEqual(name, archive.lastPathComponent)
                prompts.append(retry)
                return retry ? password : "wrong-password"
            })
            XCTAssertEqual(prompts, [false, true])
            XCTAssertEqual(try String(contentsOf: output.appendingPathComponent("secret.txt"), encoding: .utf8), "Fixture secret")
        }
    }

    func testCancellingPasswordLeavesNoExtractedFolder() throws {
        let root = try directory()
        let file = root.appendingPathComponent("original.txt")
        try Data("Original".utf8).write(to: file)
        let archive = root.appendingPathComponent("encrypted.7z")
        try fixtureCommand(["a", "-t7z", "-pfixture-password", "-mhe=on", archive.path, "original.txt"], in: root)
        var requested = false
        XCTAssertThrowsError(try archiver.extract(archive, passwordProvider: { _, _ in requested = true; return nil }))
        XCTAssertTrue(requested)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), ["original.txt", "encrypted.7z"])
    }

    func testArchivePathsCannotEscapeOutputFolder() throws {
        let root = try directory()
        let selected = root.appendingPathComponent("selected.txt")
        try Data("Archive payload".utf8).write(to: selected)
        let archive = try archiver.compress([selected])
        // 仅改变测试压缩包中的条目名，不对真实目录作向上写入。
        try fixtureCommand(["rn", archive.path, "selected.txt", "../../outside.txt"], in: root)
        let marker = root.appendingPathComponent("outside.txt")
        try Data("Keep original".utf8).write(to: marker)
        do { _ = try archiver.extract(archive) } catch { /* 拒绝不安全条目也是合法结果。 */ }
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "Keep original")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".miaoright-7z-") })
    }

    func testArchiveActionsUseNativeRuntimeAndSupportedFormats() throws {
        let compress = try XCTUnwrap(ScriptLibrary.libraryScript(named: "压缩…"))
        let extract = try XCTUnwrap(ScriptLibrary.libraryScript(named: "解压到当前文件夹"))
        XCTAssertEqual(NativeAction(script: compress.toScript()), .compressionOptions)
        XCTAssertEqual(NativeAction(script: extract.toScript()), .extractZIPHere)
        XCTAssertEqual(extract.fileExtensions, ArchiveInput.menuExtensions)
        XCTAssertTrue(ScriptLibrary.defaultEnabledActions.contains(extract.name))
    }

    func testZIPAndTARGZRemainReadableBySystemTools() throws {
        let root = try directory()
        let selected = root.appendingPathComponent("兼容性.txt")
        let data = Data("Portable archive".utf8)
        try data.write(to: selected)
        for format in [SevenZipArchive.Format.zip, .tarGzip] {
            let archive = try archiver.compress([selected], format: format)
            let output = root.appendingPathComponent("system-" + format.rawValue, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
            if format == .zip {
                try fixtureCommand(["-q", archive.path, "-d", output.path], in: root, executableURL: URL(fileURLWithPath: "/usr/bin/unzip"))
            } else {
                try fixtureCommand(["-xzf", archive.path, "-C", output.path], in: root, executableURL: URL(fileURLWithPath: "/usr/bin/tar"))
            }
            XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent(selected.lastPathComponent)), data)
        }
    }

    func testSystemArchivesAndTGZAliasCanBeExtracted() throws {
        let root = try directory()
        let name = "existing.txt"
        try Data("Existing data".utf8).write(to: root.appendingPathComponent(name))
        let zip = root.appendingPathComponent("System.ZIP")
        try fixtureCommand(["-q", zip.path, name], in: root, executableURL: URL(fileURLWithPath: "/usr/bin/zip"))
        let tgz = root.appendingPathComponent("System.TGZ")
        try fixtureCommand(["-czf", tgz.path, name], in: root, executableURL: URL(fileURLWithPath: "/usr/bin/tar"))
        for archive in [zip, tgz] {
            let output = try archiver.extract(archive)
            XCTAssertFalse(output.lastPathComponent.lowercased().hasSuffix(".tar"))
            XCTAssertEqual(try String(contentsOf: output.appendingPathComponent(name), encoding: .utf8), "Existing data")
        }
    }

    func testGzipContainingNonTarIsRejectedWithoutPublishingResults() throws {
        let root = try directory()
        let source = root.appendingPathComponent("plain.txt")
        try Data("Not a TAR stream".utf8).write(to: source)
        let archive = root.appendingPathComponent("fake.tar.gz")
        try fixtureCommand(["a", "-tgzip", archive.path, source.lastPathComponent], in: root)
        XCTAssertThrowsError(try archiver.extract(archive))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), ["plain.txt", "fake.tar.gz"])
    }

    func testBatchFailureKeepsAndIdentifiesCompletedResults() throws {
        let root = try directory()
        let selected = root.appendingPathComponent("source.txt")
        try Data("Completed".utf8).write(to: selected)
        let first = try archiver.compress([selected], format: .zip, at: root.appendingPathComponent("good.zip"))
        let broken = root.appendingPathComponent("broken.7z")
        try Data("Broken archive".utf8).write(to: broken)
        let completed = root.appendingPathComponent("good")
        XCTAssertThrowsError(try archiver.extract([first, broken])) { error in
            XCTAssertTrue(error.localizedDescription.contains(completed.path))
            XCTAssertTrue(error.localizedDescription.contains(broken.lastPathComponent))
        }
        XCTAssertEqual(try String(contentsOf: completed.appendingPathComponent("source.txt"), encoding: .utf8), "Completed")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".miaoright-7z-") })
    }

    func testLegacyComposerUsesSharedBackendAndPassesExtractedChildren() async throws {
        let root = try directory()
        let files = [root.appendingPathComponent("first.txt"), root.appendingPathComponent("second.txt")]
        for file in files { try Data(file.lastPathComponent.utf8).write(to: file) }
        let archive = try await FileOps.zip(files, archiver: archiver)
        let children = try await FileOps.unzip([archive], archiver: archiver)
        XCTAssertEqual(children.map(\.lastPathComponent), files.map(\.lastPathComponent))
        for child in children { XCTAssertEqual(try String(contentsOf: child, encoding: .utf8), child.lastPathComponent) }
        do { _ = try await FileOps.zip([], archiver: archiver); XCTFail("Empty input should fail") } catch {}
    }

    func testOOXMLWriterKeepsZIPRootAndDoesNotOverwriteExistingDocuments() throws {
        let root = try directory()
        for (suffix, part) in [("xlsx", "xl/workbook.xml"), ("pptx", "ppt/presentation.xml")] {
            let destination = root.appendingPathComponent("Document." + suffix)
            let files = ["[Content_Types].xml": "<Types/>", "_rels/.rels": "<Relationships/>", part: "<Document/>"]
            try NativeActionExecutor.createOOXMLDocument(files, at: destination, archiver: archiver)
            try fixtureCommand(["-tq", destination.path], in: root, executableURL: URL(fileURLWithPath: "/usr/bin/unzip"))
            let output = try archiver.extract(destination, format: .zip)
            for (path, contents) in files {
                XCTAssertEqual(try String(contentsOf: output.appendingPathComponent(path), encoding: .utf8), contents)
            }
            let original = try Data(contentsOf: destination)
            XCTAssertThrowsError(try NativeActionExecutor.createOOXMLDocument(files, at: destination, archiver: archiver))
            XCTAssertEqual(try Data(contentsOf: destination), original)
        }
    }
}
