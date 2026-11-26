import AppKit
import Foundation
import MiaoRightShared
import Observation

/// 仅比较版本，不把 1.10 错当成小于 1.9；构建元数据不参与优先级。
struct AppVersion: Comparable, Sendable {
    let numbers: [Int]
    let prerelease: [String]

    init?(_ value: String) {
        var value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") { value.removeFirst() }
        let metadata = value.split(separator: "+", omittingEmptySubsequences: false)
        guard metadata.count <= 2 else { return nil }
        func validIdentifier(_ part: Substring) -> Bool {
            !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }
        }
        if metadata.count == 2 {
            guard metadata[1].split(separator: ".", omittingEmptySubsequences: false).allSatisfy(validIdentifier) else { return nil }
        }
        let version = String(metadata[0])
        let dash = version.firstIndex(of: "-")
        let core = dash.map { String(version[..<$0]) } ?? version
        let components = core.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(components.count) else { return nil }
        var numbers: [Int] = []
        for part in components {
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
                  part.count == 1 || !part.hasPrefix("0"), let number = Int(part) else { return nil }
            numbers.append(number)
        }
        self.numbers = numbers + Array(repeating: 0, count: 3 - numbers.count)
        if let dash {
            let parts = version[version.index(after: dash)...].split(separator: ".", omittingEmptySubsequences: false)
            guard parts.allSatisfy(validIdentifier), parts.allSatisfy({ part in
                !part.utf8.allSatisfy { (48...57).contains($0) } || part.count == 1 || !part.hasPrefix("0")
            }) else { return nil }
            prerelease = parts.map(String.init)
        } else { prerelease = [] }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for (left, right) in zip(lhs.numbers, rhs.numbers) where left != right { return left < right }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            let leftNumeric = left.utf8.allSatisfy { (48...57).contains($0) }
            let rightNumeric = right.utf8.allSatisfy { (48...57).contains($0) }
            if leftNumeric && rightNumeric {
                return left.count == right.count ? left < right : left.count < right.count
            }
            if leftNumeric != rightNumeric { return leftNumeric }
            return left < right
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

struct UpdateRepository: Sendable {
    let slug: String
    init?(_ slug: String) {
        let parts = slug.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ part in
            !part.isEmpty && part != "." && part != ".." && part.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0)
            }
        }) else { return nil }
        self.slug = slug
    }
    var apiURL: URL { URL(string: "https://api.github.com/repos/\(slug)/releases/latest")! }
    var releasesURL: URL { URL(string: "https://github.com/\(slug)/releases")! }
    func contains(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.lowercased() == "github.com" && url.user == nil && url.password == nil && url.port == nil
            && url.path.lowercased().hasPrefix("/\(slug.lowercased())/releases/")
    }
    func containsDownload(_ url: URL) -> Bool {
        contains(url) && url.path.lowercased().hasPrefix("/\(slug.lowercased())/releases/download/")
    }
}

enum ReleaseArchitecture: String, Sendable {
    case arm64
    case x86_64

    static var current: Self {
#if arch(arm64)
        .arm64
#else
        .x86_64
#endif
    }

    var displayName: String {
        switch self {
        case .arm64: L10n.text("Apple 芯片", "Apple silicon")
        case .x86_64: L10n.text("Intel 芯片", "Intel")
        }
    }
}

struct GitHubReleaseAsset: Codable, Sendable, Equatable {
    let name: String
    let downloadURL: URL
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
        case size
    }
}

struct GitHubRelease: Codable, Sendable, Equatable {
    let name: String?
    let tagName: String
    let pageURL: URL
    let notes: String?
    let publishedAt: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubReleaseAsset]

    init(
        name: String?,
        tagName: String,
        pageURL: URL,
        notes: String?,
        publishedAt: String?,
        draft: Bool,
        prerelease: Bool,
        assets: [GitHubReleaseAsset]
    ) {
        self.name = name
        self.tagName = tagName
        self.pageURL = pageURL
        self.notes = notes
        self.publishedAt = publishedAt
        self.draft = draft
        self.prerelease = prerelease
        self.assets = assets
    }

    enum CodingKeys: String, CodingKey {
        case name, tagName = "tag_name", pageURL = "html_url", notes = "body"
        case publishedAt = "published_at", draft, prerelease, assets
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        tagName = try values.decode(String.self, forKey: .tagName)
        pageURL = try values.decode(URL.self, forKey: .pageURL)
        notes = try values.decodeIfPresent(String.self, forKey: .notes)
        publishedAt = try values.decodeIfPresent(String.self, forKey: .publishedAt)
        draft = try values.decode(Bool.self, forKey: .draft)
        prerelease = try values.decode(Bool.self, forKey: .prerelease)
        assets = try values.decodeIfPresent([GitHubReleaseAsset].self, forKey: .assets) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(name, forKey: .name)
        try values.encode(tagName, forKey: .tagName)
        try values.encode(pageURL, forKey: .pageURL)
        try values.encodeIfPresent(notes, forKey: .notes)
        try values.encodeIfPresent(publishedAt, forKey: .publishedAt)
        try values.encode(draft, forKey: .draft)
        try values.encode(prerelease, forKey: .prerelease)
        try values.encode(assets, forKey: .assets)
    }

    var publishedDate: Date? {
        guard let publishedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: publishedAt) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: publishedAt)
    }

    func installer(for architecture: ReleaseArchitecture, repository: UpdateRepository) -> GitHubReleaseAsset? {
        let expectedName = "MiaoRight-\(tagName)-\(architecture.rawValue).zip"
        return assets.first { $0.name == expectedName && repository.containsDownload($0.downloadURL) }
    }

    func checksums(repository: UpdateRepository) -> GitHubReleaseAsset? {
        assets.first { $0.name == "SHA256SUMS" && repository.containsDownload($0.downloadURL) }
    }
}

enum UpdateCheckError: Error, Equatable {
    case configuration, version, response, rateLimited, network, server(Int)
    var message: String {
        switch self {
        case .configuration: L10n.text("更新地址未配置，请联系开发者。", "The update source is not configured. Please contact the developer.")
        case .version: L10n.text("无法识别版本号，请前往发行页面查看。", "The version number is not recognized. View the release page instead.")
        case .response: L10n.text("更新信息暂时不可用，请稍后重试。", "Update information is unavailable. Please try again later.")
        case .rateLimited: L10n.text("GitHub 请求额度暂时已用尽，请稍后重试。", "GitHub’s request limit has been reached. Please try again later.")
        case .network: L10n.text("无法连接 GitHub，请检查网络后重试。", "Could not connect to GitHub. Check your connection and try again.")
        case .server: L10n.text("GitHub 暂时无法提供更新，请稍后重试。", "GitHub cannot provide updates right now. Please try again later.")
        }
    }
}

struct GitHubReleaseClient: Sendable {
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    let repository: UpdateRepository
    var load: Loader = { try await URLSession.shared.data(for: $0) }

    func latestRelease() async throws -> GitHubRelease? {
        var request = URLRequest(url: repository.apiURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("MiaoRight-Update-Checker", forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do { (data, response) = try await load(request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw UpdateCheckError.network }
        guard let http = response as? HTTPURLResponse else { throw UpdateCheckError.response }
        if http.statusCode == 404 { return nil }
        if http.statusCode == 429 || (http.statusCode == 403 && http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0") {
            throw UpdateCheckError.rateLimited
        }
        guard http.statusCode == 200 else { throw UpdateCheckError.server(http.statusCode) }
        guard data.count <= 2_000_000, let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
              repository.contains(release.pageURL),
              release.assets.allSatisfy({
                  !$0.name.isEmpty && $0.size >= 0 && repository.containsDownload($0.downloadURL)
              }) else { throw UpdateCheckError.response }
        guard !release.draft && !release.prerelease else { return nil }
        guard AppVersion(release.tagName) != nil else { throw UpdateCheckError.version }
        return release
    }
}

extension Notification.Name {
    static let showUpdatePreferences = Notification.Name("com.miaoright.showUpdatePreferences")
}

@MainActor @Observable
public final class AppUpdateService {
    public static let shared = AppUpdateService()
    static let automaticChecksKey = "appUpdateAutomaticChecks"
    static let lastCheckedAtKey = "appUpdateLastCheckedAt"
    static let cachedReleaseKey = "appUpdateCachedRelease"
    static let simulateAvailableKey = "appUpdateSimulateAvailable"
    static let checkInterval: TimeInterval = 24 * 60 * 60
    enum State: Equatable {
        case idle, checking, upToDate, noRelease
        case available(GitHubRelease)
        case failed(UpdateCheckError)
    }
    enum InstallState: Equatable {
        case idle, downloading, verifying, installing
        case failed(String)
    }
    private(set) var state: State = .idle
    private(set) var installState: InstallState = .idle
    private(set) var preferencesRequestID = 0
    private var preferencesRequested = false
    private var upToDateNoticePending = false
    private(set) var automaticallyChecksForUpdates: Bool
    private(set) var lastCheckedAt: Date?
    private(set) var canInstallInPlace: Bool
    private(set) var isProductionInstallation: Bool
    private(set) var isProductionSigned: Bool
    private(set) var simulatesAvailableUpdate: Bool
    var isDebugSimulationAvailable: Bool { !isProductionSigned }
    let repository: UpdateRepository?
    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0" }
    var isChecking: Bool { state == .checking }

    private init() {
        repository = (Bundle.main.object(forInfoDictionaryKey: "MiaoRightUpdateRepository") as? String).flatMap(UpdateRepository.init)
        let defaults = AppGroup.standardDefaults
        automaticallyChecksForUpdates = defaults.object(forKey: Self.automaticChecksKey) as? Bool ?? true
        let timestamp = defaults.double(forKey: Self.lastCheckedAtKey)
        lastCheckedAt = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        let installsInApplications = AppUpdateInstaller.isInstalledInApplications
        canInstallInPlace = installsInApplications
        let productionSigned = AppUpdateInstaller.isCurrentProductionSigned
        isProductionSigned = productionSigned
        isProductionInstallation = installsInApplications && productionSigned
        if productionSigned {
            defaults.set(false, forKey: Self.simulateAvailableKey)
            simulatesAvailableUpdate = false
        } else {
            simulatesAvailableUpdate = defaults.bool(forKey: Self.simulateAvailableKey)
        }
        if simulatesAvailableUpdate {
            lastCheckedAt = nil
        }
        if let repository,
           let data = defaults.data(forKey: Self.cachedReleaseKey),
           let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
           repository.contains(release.pageURL),
           release.assets.allSatisfy({
               !$0.name.isEmpty && $0.size >= 0 && repository.containsDownload($0.downloadURL)
           }),
           let latest = AppVersion(release.tagName),
           let current = AppVersion(Self.currentVersion),
           latest > current {
            state = .available(release)
        }
    }

    public func checkFromMenu() {
        showUpdatePreferences()
        Task { await check() }
    }

    func showUpdatePreferences() {
        preferencesRequested = true
        preferencesRequestID += 1
        WindowActionStorage.shared.showMainWindow()
        NotificationCenter.default.post(name: .showUpdatePreferences, object: nil)
    }

    func consumePreferencesRequest() -> Bool {
        defer { preferencesRequested = false }
        return preferencesRequested
    }

    func consumeUpToDateNotice() -> Bool {
        defer { upToDateNoticePending = false }
        return upToDateNoticePending
    }

    func check() async {
        await performCheck(silentFailure: false)
    }

    public func checkIfDue(now: Date = .now) async {
        guard automaticallyChecksForUpdates, !isChecking else { return }
        if let lastCheckedAt, now.timeIntervalSince(lastCheckedAt) < Self.checkInterval { return }
        await performCheck(silentFailure: true)
    }

    func setAutomaticallyChecksEnabled(_ enabled: Bool) {
        AppGroup.standardDefaults.set(enabled, forKey: Self.automaticChecksKey)
        automaticallyChecksForUpdates = enabled
        guard enabled else { return }
        Task { await checkIfDue() }
    }

    func setSimulatesAvailableUpdate(_ enabled: Bool) {
        guard isDebugSimulationAvailable else { return }
        AppGroup.standardDefaults.set(enabled, forKey: Self.simulateAvailableKey)
        simulatesAvailableUpdate = enabled
        clearCachedRelease()
        state = .idle
        Task { await check() }
    }

    var isInstalling: Bool {
        switch installState {
        case .downloading, .verifying, .installing: true
        default: false
        }
    }

    func installUpdate(_ release: GitHubRelease) async {
        await performInstall(release: release)
    }

    private func performInstall(release: GitHubRelease) async {
        guard !isInstalling else { return }
        guard canInstallInPlace else {
            installState = .failed(AppUpdateInstallError.notInstalledInApplications.localizedDescription)
            return
        }

        let stagingDirectory: URL
        do {
            stagingDirectory = try AppUpdateInstaller.makeStagingDirectory()
        } catch {
            installState = .failed(error.localizedDescription)
            return
        }

        var replacementStarted = false
        do {
            guard let repository,
                  let asset = release.installer(for: .current, repository: repository) else {
                throw AppUpdateInstallError.missingArchive
            }
            installState = .downloading
            let archive = try await AppUpdateInstaller.download(asset, into: stagingDirectory)
            installState = .verifying

            let prepared = try await Task.detached(priority: .userInitiated) {
                try AppUpdateInstaller.prepare(
                    archiveURL: archive,
                    expectedTag: release.tagName,
                    stagingDirectory: stagingDirectory
                )
            }.value
            installState = .installing
            try AppUpdateInstaller.launchReplacement(prepared, currentPID: getpid())
            replacementStarted = true
            NSApplication.shared.terminate(nil)
        } catch {
            if !replacementStarted {
                try? FileManager.default.removeItem(at: stagingDirectory)
            }
            installState = .failed(error.localizedDescription)
        }
    }

    private func performCheck(silentFailure: Bool) async {
        guard !isChecking else { return }
        upToDateNoticePending = false
        let previousState = state
        state = .checking
        guard let repository else {
            state = silentFailure ? previousState : .failed(.configuration)
            return
        }
        guard let current = AppVersion(Self.currentVersion) else {
            state = silentFailure ? previousState : .failed(.version)
            return
        }
        do {
            let release: GitHubRelease?
            do {
                release = try await GitHubReleaseClient(repository: repository).latestRelease()
            } catch UpdateCheckError.rateLimited {
                release = try await GitHubAtomReleaseClient(repository: repository).latestRelease()
            }
            guard let release else {
                markChecked()
                clearCachedRelease()
                state = .noRelease
                return
            }
            guard let latest = AppVersion(release.tagName) else {
                state = silentFailure ? previousState : .failed(.version)
                return
            }
            markChecked()
            let offersUpdate: Bool
            if simulatesAvailableUpdate, isDebugSimulationAvailable {
                offersUpdate = latest >= current
            } else {
                offersUpdate = latest > current
            }
            if offersUpdate {
                cache(release)
                state = .available(release)
            } else {
                clearCachedRelease()
                upToDateNoticePending = true
                state = .upToDate
            }
        } catch is CancellationError { state = silentFailure ? previousState : .idle }
        catch let error as UpdateCheckError { state = silentFailure ? previousState : .failed(error) }
        catch { state = silentFailure ? previousState : .failed(.network) }
    }

    private func markChecked(at date: Date = .now) {
        lastCheckedAt = date
        AppGroup.standardDefaults.set(date.timeIntervalSince1970, forKey: Self.lastCheckedAtKey)
    }

    private func cache(_ release: GitHubRelease) {
        guard let data = try? JSONEncoder().encode(release) else { return }
        AppGroup.standardDefaults.set(data, forKey: Self.cachedReleaseKey)
    }

    private func clearCachedRelease() {
        AppGroup.standardDefaults.removeObject(forKey: Self.cachedReleaseKey)
    }
}
