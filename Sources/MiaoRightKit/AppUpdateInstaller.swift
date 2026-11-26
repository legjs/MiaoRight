import AppKit
import Foundation
import MiaoRightShared

enum AppUpdateInstallError: LocalizedError, Equatable {
    case notInstalledInApplications
    case missingReleaseCertificate
    case missingArchive
    case downloadFailed
    case invalidArchive
    case invalidBundle
    case wrongVersion
    case wrongCertificate
    case wrongArchitecture
    case extractionFailed(String)
    case installationFailed

    var errorDescription: String? {
        switch self {
        case .notInstalledInApplications:
            L10n.text(
                "自动更新只支持 /Applications/MiaoRight.app。请先把妙右移入“应用程序”文件夹。",
                "Automatic updates require /Applications/MiaoRight.app. Move MiaoRight to Applications first."
            )
        case .missingReleaseCertificate:
            L10n.text(
                "更新包缺少发布签名校验信息，请重新构建。",
                "The update package is missing its release-signing information. Rebuild the app."
            )
        case .missingArchive:
            L10n.text("没有可安装的更新包。", "No update archive is available.")
        case .downloadFailed:
            L10n.text(
                "无法直接下载更新。请打开发行页面下载 ZIP，再选择该 ZIP 安装。",
                "Could not download the update directly. Download the ZIP from the release page, then choose it to install."
            )
        case .invalidArchive:
            L10n.text(
                "更新包不是有效的 ZIP 压缩包。",
                "The update is not a valid ZIP archive."
            )
        case .invalidBundle:
            L10n.text(
                "更新包中没有有效的妙右 App。",
                "The update archive does not contain a valid MiaoRight app."
            )
        case .wrongVersion:
            L10n.text(
                "更新包版本与发行版本不一致。",
                "The app version does not match the release version."
            )
        case .wrongCertificate:
            L10n.text(
                "更新包不是由妙右发布证书签名，已停止安装。",
                "The update is not signed by the MiaoRight release certificate, so installation stopped."
            )
        case .wrongArchitecture:
            L10n.text(
                "更新包架构与当前 Mac 不匹配。",
                "The update architecture does not match this Mac."
            )
        case .extractionFailed(let detail):
            L10n.text("解压更新包失败：", "Could not extract the update: ") + detail
        case .installationFailed:
            L10n.text(
                "无法启动更新安装程序。原版本已保留，请重试。",
                "Could not start the update installer. The previous version was retained; try again."
            )
        }
    }
}

struct PreparedAppUpdate: Sendable {
    let stagingDirectory: URL
    let candidateApp: URL
    let helperScript: URL
    let logURL: URL
}

enum AppUpdateInstaller {
    static let installedAppURL = URL(fileURLWithPath: "/Applications/MiaoRight.app", isDirectory: true)
    static let bundleIdentifier = "com.miaoright.app"
    private static let certificateInfoKey = "MiaoRightReleaseSigningCertificateSHA1"

    static var expectedCertificateSHA1: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: certificateInfoKey) as? String else { return nil }
        let normalized = normalizeFingerprint(value)
        return normalized.isEmpty ? nil : normalized
    }

    static var isInstalledInApplications: Bool {
        Bundle.main.bundleURL.standardizedFileURL == installedAppURL.standardizedFileURL
    }

    static var isCurrentProductionInstallation: Bool {
        isInstalledInApplications && isCurrentProductionSigned
    }

    static var isCurrentProductionSigned: Bool {
        guard let expectedCertificateSHA1 else { return false }
        guard let requirement = try? designatedRequirement(for: Bundle.main.bundleURL) else { return false }
        return requirementContainsCertificate(requirement, fingerprint: expectedCertificateSHA1)
    }

    static func makeStagingDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiaoRightUpdate-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return url
    }

    static func download(_ asset: GitHubReleaseAsset, into stagingDirectory: URL) async throws -> URL {
        var request = URLRequest(url: asset.downloadURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("MiaoRight-Update-Installer", forHTTPHeaderField: "User-Agent")

        let downloadedURL: URL
        let response: URLResponse
        do {
            (downloadedURL, response) = try await URLSession.shared.download(for: request)
        } catch {
            throw AppUpdateInstallError.downloadFailed
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppUpdateInstallError.downloadFailed
        }

        let archiveURL = stagingDirectory.appendingPathComponent(asset.name)
        do {
            try FileManager.default.moveItem(at: downloadedURL, to: archiveURL)
            let attributes = try FileManager.default.attributesOfItem(atPath: archiveURL.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard (asset.size == 0 || size == Int64(asset.size)), isZIPFile(archiveURL) else {
                throw AppUpdateInstallError.invalidArchive
            }
        } catch let error as AppUpdateInstallError {
            throw error
        } catch {
            throw AppUpdateInstallError.downloadFailed
        }
        return archiveURL
    }

    static func prepare(
        archiveURL: URL,
        expectedTag: String,
        stagingDirectory: URL,
        extractorURL: URL? = nil,
        certificateSHA1: String? = nil
    ) throws -> PreparedAppUpdate {
        guard archiveURL.pathExtension.lowercased() == "zip", isZIPFile(archiveURL) else {
            throw AppUpdateInstallError.invalidArchive
        }
        guard let expectedCertificateSHA1 = certificateSHA1 ?? Self.expectedCertificateSHA1 else {
            throw AppUpdateInstallError.missingReleaseCertificate
        }

        let extractionDirectory = stagingDirectory.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractionDirectory, withIntermediateDirectories: false)
        let extractor = extractorURL ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/7zz")
        guard FileManager.default.isExecutableFile(atPath: extractor.path) else {
            throw AppUpdateInstallError.extractionFailed(L10n.text("内置 7-Zip 缺失。", "The bundled 7-Zip tool is missing."))
        }
        try runExtractor(extractor, archive: archiveURL, destination: extractionDirectory)

        let candidateApp = extractionDirectory.appendingPathComponent("MiaoRight.app", isDirectory: true)
        let candidateValues = try? candidateApp.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard isDirectory(candidateApp), candidateValues?.isSymbolicLink != true else {
            throw AppUpdateInstallError.invalidBundle
        }
        try validate(candidateApp, expectedTag: expectedTag, expectedCertificateSHA1: expectedCertificateSHA1)

        let helperScript = stagingDirectory.appendingPathComponent("install-update.sh")
        let logDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MiaoRight", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let logURL = logDirectory.appendingPathComponent("update.log")
        let script = """
        #!/bin/sh
        set -u
        target="$1"
        candidate="$2"
        pid="$3"
        log="$4"
        staging="$5"
        backup="${target}.previous"
        exec >>"$log" 2>&1
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting update"
        /usr/bin/pkill -f "$target/Contents/PlugIns/MiaoRightFinder.appex/Contents/MacOS/MiaoRightFinder" 2>/dev/null || true
        /usr/bin/pkill -f "$target/Contents/PlugIns/MiaoRightArchivePreview.appex/Contents/MacOS/MiaoRightArchivePreview" 2>/dev/null || true
        while /bin/kill -0 "$pid" 2>/dev/null; do /bin/sleep 0.2; done
        /bin/rm -rf "$backup"
        if ! /bin/mv "$target" "$backup"; then
          echo "Failed to move the existing app"
          /usr/bin/open "$target"
          exit 10
        fi
        if ! /usr/bin/ditto "$candidate" "$target"; then
          echo "Failed to copy the update; restoring the previous app"
          /bin/rm -rf "$target"
          /bin/mv "$backup" "$target"
          /usr/bin/open "$target"
          exit 11
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$target" 2>/dev/null || true
        /bin/rm -rf "$backup"
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$target"
        /usr/bin/killall Finder 2>/dev/null || true
        /usr/bin/open "$target"
        /bin/rm -rf "$staging"
        """
        try script.write(to: helperScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperScript.path)
        return PreparedAppUpdate(
            stagingDirectory: stagingDirectory,
            candidateApp: candidateApp,
            helperScript: helperScript,
            logURL: logURL
        )
    }

    static func launchReplacement(_ prepared: PreparedAppUpdate, currentPID: Int32) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            prepared.helperScript.path,
            installedAppURL.path,
            prepared.candidateApp.path,
            String(currentPID),
            prepared.logURL.path,
            prepared.stagingDirectory.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw AppUpdateInstallError.installationFailed
        }
    }

    private static func validate(_ candidateApp: URL, expectedTag: String, expectedCertificateSHA1: String) throws {
        guard let bundle = Bundle(url: candidateApp),
              bundle.bundleIdentifier == bundleIdentifier,
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        else {
            throw AppUpdateInstallError.invalidBundle
        }
        guard let candidateVersion = AppVersion("v" + version),
              let expectedVersion = AppVersion(expectedTag),
              candidateVersion == expectedVersion else {
            throw AppUpdateInstallError.wrongVersion
        }

        try runChecked("/usr/bin/codesign", ["--verify", "--deep", "--strict", candidateApp.path])
        let requirement = try designatedRequirement(for: candidateApp)
        guard requirementContainsCertificate(requirement, fingerprint: expectedCertificateSHA1) else {
            throw AppUpdateInstallError.wrongCertificate
        }

        let pluginDirectory = candidateApp.appendingPathComponent("Contents/PlugIns", isDirectory: true)
        let plugins = (try? FileManager.default.contentsOfDirectory(
            at: pluginDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.filter { $0.pathExtension == "appex" } ?? []
        for plugin in plugins {
            let pluginRequirement = try designatedRequirement(for: plugin)
            guard requirementContainsCertificate(pluginRequirement, fingerprint: expectedCertificateSHA1) else {
                throw AppUpdateInstallError.wrongCertificate
            }
        }

        let executable = candidateApp.appendingPathComponent("Contents/MacOS/MiaoRight")
        let architectures = try capture("/usr/bin/lipo", ["-archs", executable.path])
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard architectures.contains(ReleaseArchitecture.current.rawValue) else {
            throw AppUpdateInstallError.wrongArchitecture
        }
    }

    private static func designatedRequirement(for url: URL) throws -> String {
        do {
            return try capture("/usr/bin/codesign", ["-d", "-r-", url.path])
        } catch {
            throw AppUpdateInstallError.wrongCertificate
        }
    }

    private static func requirementContainsCertificate(_ requirement: String, fingerprint: String) -> Bool {
        requirement.lowercased().contains("certificate leaf = h\"\(fingerprint.lowercased())\"")
    }

    private static func normalizeFingerprint(_ value: String) -> String {
        value.lowercased().filter { $0.isHexDigit }
    }

    private static func isZIPFile(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let signature = try? handle.read(upToCount: 2)
        return signature == Data([0x50, 0x4B])
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func runExtractor(_ executable: URL, archive: URL, destination: URL) throws {
        let process = Process()
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoRightUpdate-7z.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer { try? FileManager.default.removeItem(at: logURL) }

        let logHandle = try FileHandle(forWritingTo: logURL)
        defer { try? logHandle.close() }
        process.executableURL = executable
        process.arguments = ["x", "-y", "-bd", "-bso0", "-bsp0", "-bse1", "-o" + destination.path, "--", archive.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = logHandle
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let end = try logHandle.seekToEnd()
            try logHandle.seek(toOffset: max(0, end - 2_000))
            let detail = String(decoding: try logHandle.readToEnd() ?? Data(), as: UTF8.self)
            throw AppUpdateInstallError.extractionFailed(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func runChecked(_ executable: String, _ arguments: [String]) throws {
        _ = try capture(executable, arguments)
    }

    private static func capture(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw AppUpdateInstallError.installationFailed
        }
        return output
    }
}
