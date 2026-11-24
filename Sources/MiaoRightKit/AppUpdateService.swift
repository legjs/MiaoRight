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
}

struct GitHubRelease: Decodable, Sendable, Equatable {
    let tagName: String
    let pageURL: URL
    let notes: String?
    let draft: Bool
    let prerelease: Bool
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", pageURL = "html_url", notes = "body", draft, prerelease
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
              repository.contains(release.pageURL) else { throw UpdateCheckError.response }
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
    enum State: Equatable {
        case idle, checking, upToDate, noRelease
        case available(GitHubRelease)
        case failed(UpdateCheckError)
    }
    private(set) var state: State = .idle
    private(set) var preferencesRequestID = 0
    private var preferencesRequested = false
    let repository: UpdateRepository?
    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0" }
    var isChecking: Bool { state == .checking }

    private init() {
        repository = (Bundle.main.object(forInfoDictionaryKey: "MiaoRightUpdateRepository") as? String).flatMap(UpdateRepository.init)
    }

    public func checkFromMenu() {
        preferencesRequested = true
        preferencesRequestID += 1
        WindowActionStorage.shared.showMainWindow()
        NotificationCenter.default.post(name: .showUpdatePreferences, object: nil)
        Task { await check() }
    }

    func consumePreferencesRequest() -> Bool {
        defer { preferencesRequested = false }
        return preferencesRequested
    }

    func check() async {
        guard !isChecking else { return }
        state = .checking
        guard let repository else { state = .failed(.configuration); return }
        guard let current = AppVersion(Self.currentVersion) else { state = .failed(.version); return }
        do {
            guard let release = try await GitHubReleaseClient(repository: repository).latestRelease() else { state = .noRelease; return }
            guard let latest = AppVersion(release.tagName) else { state = .failed(.version); return }
            state = latest > current ? .available(release) : .upToDate
        } catch is CancellationError { state = .idle }
        catch let error as UpdateCheckError { state = .failed(error) }
        catch { state = .failed(.network) }
    }
}
