import Foundation
import MiaoRightArchivePreviewKit
import XCTest
@testable import MiaoRightKit

final class ArchiveEnhancementTests: XCTestCase {
    private var executable: URL {
        ProcessInfo.processInfo.environment["MIAORIGHT_TEST_7ZZ_PATH"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ThirdParty/7zip/7zz")
    }
    private var archiver: SevenZipArchive { SevenZipArchive(executableURL: executable) }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoRight-ArchiveFeatures-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }
    private func fixture(_ arguments: [String], at root: URL) throws {
        let process = Process()
        process.executableURL = executable; process.arguments = arguments; process.currentDirectoryURL = root
        process.standardInput = FileHandle.nullDevice; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    func testEncryptedCompressionUsesPasswordAndRoundTripsZIPAnd7Z() throws {
        let root = try directory(), selected = root.appendingPathComponent("secret.txt")
        try Data("The encrypted contents".utf8).write(to: selected)
        for format in [SevenZipArchive.Format.zip, .sevenZip] {
            let password = format == .zip ? "Fixture-password-123" : "Fixture-密码-123"
            let archive = try archiver.compress([selected], format: format, password: password)
            var requested = false
            let output = try archiver.extract(archive, passwordProvider: { _, retry in
                XCTAssertFalse(retry); requested = true; return password
            })
            XCTAssertTrue(requested, "An unencrypted archive would never ask for a password")
            XCTAssertEqual(try String(contentsOf: output.appendingPathComponent("secret.txt"), encoding: .utf8), "The encrypted contents")
        }
        XCTAssertThrowsError(try archiver.compress([selected], format: .tarGzip, password: "not-supported"))
        XCTAssertThrowsError(try archiver.compress([selected], format: .zip, password: "中文密码"))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".miaoright-7z-") })
    }

    func testSingleStreamsAndTarStreamsAreDetected() throws {
        let root = try directory(), file = root.appendingPathComponent("content.txt")
        try Data("Portable contents".utf8).write(to: file)
        try fixture(["a", "-ttar", "content.tar", "content.txt"], at: root)
        for (type, suffix) in [("gzip", "gz"), ("xz", "xz"), ("bzip2", "bz2")] {
            let plain = root.appendingPathComponent("content.txt." + suffix)
            try fixture(["a", "-t" + type, plain.path, "content.txt"], at: root)
            let output = try archiver.extract(plain)
            XCTAssertEqual(try String(contentsOf: output.appendingPathComponent("content.txt"), encoding: .utf8), "Portable contents")
            let wrapped = root.appendingPathComponent("content.tar." + suffix)
            try fixture(["a", "-t" + type, wrapped.path, "content.tar"], at: root)
            let unwrapped = try archiver.extract(wrapped)
            XCTAssertEqual(try String(contentsOf: unwrapped.appendingPathComponent("content.txt"), encoding: .utf8), "Portable contents")
        }
        let tarOutput = try archiver.extract(root.appendingPathComponent("content.tar"))
        XCTAssertEqual(try String(contentsOf: tarOutput.appendingPathComponent("content.txt"), encoding: .utf8), "Portable contents")
    }

    func testCommon7ZAndZIPVolumesDeduplicateAndMissingPartLeavesNoPartialFolder() throws {
        let root = try directory(), selected = root.appendingPathComponent("data.bin")
        let bytes = Data((0..<9000).map { UInt8($0 % 251) })
        try bytes.write(to: selected)
        for kind in ["7z", "zip"] {
            let archive = root.appendingPathComponent("parts-" + kind + "." + kind)
            try fixture(["a", "-t" + kind, "-mx=0", "-v1k", archive.path, "data.bin"], at: root)
            let first = URL(fileURLWithPath: archive.path + ".001"), second = URL(fileURLWithPath: archive.path + ".002")
            XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
            let outputs = try archiver.extract([first, second])
            XCTAssertEqual(outputs.count, 1)
            XCTAssertEqual(try Data(contentsOf: outputs[0].appendingPathComponent("data.bin")), bytes)
            try FileManager.default.removeItem(at: second)
            XCTAssertThrowsError(try archiver.extract(first))
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".miaoright-7z-") })
        }
    }

    func testMissingFirstVolumeReportsUsefulError() throws {
        let root = try directory(), later = root.appendingPathComponent("missing.7z.002")
        try Data("later volume".utf8).write(to: later)
        XCTAssertThrowsError(try ArchiveInput(later)) { error in XCTAssertTrue(error.localizedDescription.contains("missing.7z.001")) }
        let first = root.appendingPathComponent("backup.PART01.RAR")
        try Data("first".utf8).write(to: first)
        let input = try ArchiveInput(root.appendingPathComponent("backup.PART02.RAR"))
        XCTAssertEqual(input.url.lastPathComponent, first.lastPathComponent)
        XCTAssertEqual(input.extractedName, "backup")
    }

    func testRARFixtureExtractsRealContents() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Archives/libarchive-basic.rar.uu")
        let text = try String(contentsOf: fixtureURL, encoding: .utf8)
        var data = Data()
        for line in text.split(separator: "\n").dropFirst() {
            if line == "end" { break }
            let bytes = Array(line.utf8)
            guard let first = bytes.first else { continue }
            let length = Int((first &- 32) & 63)
            var decoded: [UInt8] = []
            var index = 1
            while index + 3 < bytes.count {
                let a = (bytes[index] &- 32) & 63, b = (bytes[index + 1] &- 32) & 63
                let c = (bytes[index + 2] &- 32) & 63, d = (bytes[index + 3] &- 32) & 63
                decoded += [(a << 2) | (b >> 4), (b << 4) | (c >> 2), (c << 6) | d]
                index += 4
            }
            data.append(contentsOf: decoded.prefix(length))
        }
        let root = try directory(), archive = root.appendingPathComponent("basic.rar")
        try data.write(to: archive)
        let directory = try ArchiveDirectory.read(archive)
        XCTAssertTrue(directory.entries.contains { $0.name == "test.txt" })
        XCTAssertTrue(directory.entries.first { $0.name == "testdir" }?.children?.contains { $0.name == "test.txt" } == true)
        let output = try archiver.extract(archive)
        XCTAssertEqual(try String(contentsOf: output.appendingPathComponent("test.txt"), encoding: .utf8), "test text document\r\n")
        XCTAssertEqual(try String(contentsOf: output.appendingPathComponent("testdir/test.txt"), encoding: .utf8), "test text document\r\n")
    }

    func testDuplicateZIPEntriesArePreservedWithoutOverwriting() throws {
        let fixture = "UEsDBBQAAAAAAMdIc11X7nGSBQAAAAUAAAAIAAAAc2FtZS50eHRmaXJzdFBLAwQUAAAAAADHSHNdaREftgYAAAAGAAAACAAAAHNhbWUudHh0c2Vjb25kUEsBAhQDFAAAAAAAx0hzXVfucZIFAAAABQAAAAgAAAAAAAAAAAAAAIABAAAAAHNhbWUudHh0UEsBAhQDFAAAAAAAx0hzXWkRH7YGAAAABgAAAAgAAAAAAAAAAAAAAIABKwAAAHNhbWUudHh0UEsFBgAAAAACAAIAbAAAAFcAAAAAAA=="
        let root = try directory(), archive = root.appendingPathComponent("duplicate.zip")
        try XCTUnwrap(Data(base64Encoded: fixture)).write(to: archive)
        let output = try archiver.extract(archive)
        let children = try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(Set(try children.map { try String(contentsOf: $0, encoding: .utf8) }), ["first", "second"])
    }

    func testPasswordInCorruptFileNameDoesNotOpenPasswordPrompt() throws {
        let root = try directory(), archive = root.appendingPathComponent("password-backup.zip")
        try Data("not an archive".utf8).write(to: archive)
        var requested = false
        XCTAssertThrowsError(try archiver.extract(archive, passwordProvider: { _, _ in requested = true; return "unused" }))
        XCTAssertFalse(requested)
    }
}
