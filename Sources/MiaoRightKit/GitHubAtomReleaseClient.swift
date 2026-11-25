import Foundation

/// Fallback for GitHub's unauthenticated API limit. The HTML/Atom release feed
/// and raw repository files are not part of the REST API quota.
struct GitHubAtomReleaseClient: Sendable {
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let repository: UpdateRepository
    var load: Loader = { try await URLSession.shared.data(for: $0) }

    func latestRelease() async throws -> GitHubRelease? {
        let feedURL = URL(string: "https://github.com/\(repository.slug)/releases.atom")!
        var request = URLRequest(url: feedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("MiaoRight-Update-Checker", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await load(request)
        } catch {
            throw UpdateCheckError.network
        }
        guard let http = response as? HTTPURLResponse else { throw UpdateCheckError.response }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200, data.count <= 2_000_000 else { throw UpdateCheckError.response }
        guard let xml = String(data: data, encoding: .utf8) else { throw UpdateCheckError.response }

        for entry in entries(in: xml) {
            guard let pageURL = entry.pageURL,
                  repository.contains(pageURL),
                  let tag = pageURL.pathComponents.last,
                  let version = AppVersion(tag),
                  version.prerelease.isEmpty
            else { continue }

            let notes = await loadNotes(tag: tag)
            let assets = await loadAssets(tag: tag)
            return GitHubRelease(
                name: entry.title,
                tagName: tag,
                pageURL: pageURL,
                notes: notes,
                publishedAt: entry.updated,
                draft: false,
                prerelease: false,
                assets: assets
            )
        }
        return nil
    }

    private struct Entry {
        let pageURL: URL?
        let title: String?
        let updated: String?
    }

    private func entries(in xml: String) -> [Entry] {
        matches(#"<entry>(.*?)</entry>"#, in: xml).compactMap { entry in
            let link = matches(#"<link\s+rel="alternate"\s+type="text/html"\s+href="([^"]+)""#, in: entry).first
            return Entry(
                pageURL: link.flatMap(URL.init(string:)),
                title: matches(#"<title>(.*?)</title>"#, in: entry).first.map(decodeXML),
                updated: matches(#"<updated>(.*?)</updated>"#, in: entry).first
            )
        }
    }

    private func loadNotes(tag: String) async -> String? {
        guard let url = URL(string: "https://raw.githubusercontent.com/\(repository.slug)/\(tag)/docs/release-notes/\(tag).md") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("MiaoRight-Update-Checker", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await load(request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= 2_000_000
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func loadAssets(tag: String) async -> [GitHubReleaseAsset] {
        var assets: [GitHubReleaseAsset] = []
        for architecture in [ReleaseArchitecture.arm64, .x86_64] {
            let name = "MiaoRight-\(tag)-\(architecture.rawValue).zip"
            guard let url = URL(string: "https://github.com/\(repository.slug)/releases/download/\(tag)/\(name)"),
                  repository.containsDownload(url)
            else { continue }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.httpMethod = "HEAD"
            request.setValue("MiaoRight-Update-Checker", forHTTPHeaderField: "User-Agent")
            let size: Int
            if let (_, response) = try? await load(request) {
                size = Int(max(0, response.expectedContentLength))
            } else {
                size = 0
            }
            assets.append(GitHubReleaseAsset(name: name, downloadURL: url, size: size))
        }
        return assets
    }

    private func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    private func decodeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
