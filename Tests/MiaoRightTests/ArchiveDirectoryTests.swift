import Foundation
import MiaoRightArchivePreviewKit
import XCTest
@testable import MiaoRightKit

final class ArchiveDirectoryTests: XCTestCase {
    private func withArchiveFixture(_ check: (URL, URL, SevenZipArchive) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("项目")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent("总结.txt"))
        try Data([4, 5]).write(to: folder.appendingPathComponent("报告.txt"))
        try check(root, folder, SevenZipArchive(executableURL: ArchiveTestTool.executableURL))
    }

    func testDirectoryMetadataAcrossZipSevenZipAndTarGzip() throws {
        try withArchiveFixture { root, folder, archiver in
            for format in [SevenZipArchive.Format.zip, .sevenZip, .tarGzip] {
                let archive = try archiver.compress([folder], format: format)
                let before = try Set(FileManager.default.contentsOfDirectory(atPath: root.path))
                let result = try ArchiveDirectory.read(archive)
                XCTAssertEqual(result.files, 2, "\(format)")
                XCTAssertEqual(result.folders, 1)
                XCTAssertEqual(result.bytes, 5)
                XCTAssertFalse(result.isPartial)
                XCTAssertEqual(result.entries.first?.name, "项目")
                XCTAssertEqual(Set(result.entries.first?.children?.map(\.name) ?? []), ["总结.txt", "报告.txt"])
                XCTAssertEqual(try Set(FileManager.default.contentsOfDirectory(atPath: root.path)), before)
            }
        }
    }

    func testLargeListingReportsPartialAndRejectsBadArchive() throws {
        try withArchiveFixture { root, folder, archiver in
            let archive = try archiver.compress([folder], format: .zip)
            XCTAssertTrue(try ArchiveDirectory.read(archive, entryLimit: 1).isPartial)
            let bad = root.appendingPathComponent("bad.zip")
            try Data("not an archive".utf8).write(to: bad)
            XCTAssertThrowsError(try ArchiveDirectory.read(bad))
        }
    }

    func testEncryptedDirectoryHasSpecificError() throws {
        try withArchiveFixture { _, folder, archiver in
            let archive = try archiver.compress([folder], format: .sevenZip, password: "preview-fixture")
            XCTAssertThrowsError(try ArchiveDirectory.read(archive)) { error in
                guard case ArchiveDirectory.ReadError.encrypted = error else {
                    return XCTFail("Expected an encrypted directory, got \(error)")
                }
            }
        }
    }
}
