import Foundation
import XCTest
@testable import MiaoRightKit

final class AppUpdateInstallerTests: XCTestCase {
    func testPreparedUpdateValidatesSignedArchive() throws {
        let identity = "MiaoRight Release"
        let identities = try run("/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"]).output
        guard identities.contains("\"\(identity)\"") else {
            throw XCTSkip("MiaoRight Release signing identity is not installed")
        }

        let fixture = try makeFixture(identity: identity)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let prepared = try AppUpdateInstaller.prepare(
            archiveURL: fixture.archive,
            expectedTag: "v9.9.9",
            stagingDirectory: fixture.staging,
            extractorURL: repositoryRoot.appendingPathComponent("ThirdParty/7zip/7zz"),
            certificateSHA1: fixture.certificateSHA1
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.candidateApp.path))
        XCTAssertTrue(prepared.helperScript.path.hasPrefix(fixture.staging.path))
        XCTAssertEqual(Bundle(url: prepared.candidateApp)?.bundleIdentifier, AppUpdateInstaller.bundleIdentifier)
        let scriptCheck = try run("/bin/sh", ["-n", prepared.helperScript.path])
        XCTAssertEqual(scriptCheck.status, 0, scriptCheck.output)
    }

    func testPreparedUpdateRejectsAdHocSignature() throws {
        let fixture = try makeFixture(identity: "-")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        XCTAssertThrowsError(try AppUpdateInstaller.prepare(
            archiveURL: fixture.archive,
            expectedTag: "v9.9.9",
            stagingDirectory: fixture.staging,
            extractorURL: repositoryRoot.appendingPathComponent("ThirdParty/7zip/7zz"),
            certificateSHA1: "0123456789abcdef0123456789abcdef01234567"
        )) { error in
            XCTAssertEqual(error as? AppUpdateInstallError, .wrongCertificate)
        }
    }

    private struct Fixture {
        let root: URL
        let staging: URL
        let archive: URL
        let certificateSHA1: String
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func makeFixture(identity: String) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiaoRightInstallerTests-" + UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let app = source.appendingPathComponent("MiaoRight.app", isDirectory: true)
        let executableDirectory = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
        let executable = executableDirectory.appendingPathComponent("MiaoRight")
        let toolName = ReleaseArchitecture.current == .arm64 ? "7zz" : "7zz-x86_64"
        try FileManager.default.copyItem(
            at: repositoryRoot.appendingPathComponent("ThirdParty/7zip/" + toolName),
            to: executable
        )

        let info: [String: Any] = [
            "CFBundleIdentifier": AppUpdateInstaller.bundleIdentifier,
            "CFBundleExecutable": "MiaoRight",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "9.9.9",
            "CFBundleVersion": "999"
        ]
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: app.appendingPathComponent("Contents/Info.plist"))

        let signArguments = ["--force", "--deep", "--identifier", AppUpdateInstaller.bundleIdentifier, "--sign", identity, app.path]
        let sign = try run("/usr/bin/codesign", signArguments)
        XCTAssertEqual(sign.status, 0, sign.output)

        let certificateSHA1: String
        if identity == "-" {
            certificateSHA1 = "0123456789abcdef0123456789abcdef01234567"
        } else {
            let requirement = try run("/usr/bin/codesign", ["-d", "-r-", app.path]).output
            certificateSHA1 = try XCTUnwrap(extractCertificateFingerprint(from: requirement))
        }

        let archive = root.appendingPathComponent("MiaoRight-v9.9.9-arm64.zip")
        let zip = try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", app.path, archive.path])
        XCTAssertEqual(zip.status, 0, zip.output)

        let staging = root.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        return Fixture(root: root, staging: staging, archive: archive, certificateSHA1: certificateSHA1)
    }

    private func extractCertificateFingerprint(from requirement: String) -> String? {
        guard let range = requirement.range(of: "certificate leaf = H\"", options: .caseInsensitive) else { return nil }
        let suffix = requirement[range.upperBound...]
        guard let end = suffix.firstIndex(of: "\"") else { return nil }
        return String(suffix[..<end]).lowercased()
    }

    @discardableResult
    private func run(_ executable: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
