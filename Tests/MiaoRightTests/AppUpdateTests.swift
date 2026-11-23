import Foundation
import XCTest
@testable import MiaoRightKit

final class AppUpdateTests: XCTestCase {
    func testVersionOrderingAndBuildMetadata() throws {
        XCTAssertGreaterThan(try XCTUnwrap(AppVersion("v1.10.0")), try XCTUnwrap(AppVersion("1.9.9")))
        XCTAssertEqual(AppVersion("1.0"), AppVersion("1.0.0+build.101"))
        let versions = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-beta", "1.0.0-rc.2", "1.0.0-rc.10", "1.0.0"]
        let parsed = try versions.map { try XCTUnwrap(AppVersion($0)) }
        for (older, newer) in zip(parsed, parsed.dropFirst()) { XCTAssertLessThan(older, newer) }
        for invalid in ["", "release", "1..0", "01.0.0", "1.0.0-", "1.0.0-rc.01", "1.0.0+", "1.0.0+bad+metadata"] {
            XCTAssertNil(AppVersion(invalid), invalid)
        }
    }

    private func client(status: Int = 200, headers: [String: String] = [:], body: String = "") -> GitHubReleaseClient {
        GitHubReleaseClient(repository: UpdateRepository("legjs/MiaoRight")!, load: { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/legjs/MiaoRight/releases/latest")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
        })
    }

    private func release(tag: String = "v1.1.0", url: String = "https://github.com/legjs/MiaoRight/releases/tag/v1.1.0", prerelease: Bool = false) -> String {
        "{\"tag_name\":\"\(tag)\",\"html_url\":\"\(url)\",\"body\":\"Release notes\",\"draft\":false,\"prerelease\":\(prerelease)}"
    }

    func testPublicReleaseAndMissingReleaseAreDistinct() async throws {
        let available = try await client(body: release()).latestRelease()
        XCTAssertEqual(available?.tagName, "v1.1.0")
        XCTAssertEqual(available?.notes, "Release notes")
        let absent = try await client(status: 404).latestRelease()
        XCTAssertNil(absent)
        let beta = try await client(body: release(tag: "v2.0.0-beta.1", prerelease: true)).latestRelease()
        XCTAssertNil(beta)
    }

    func testFailuresDoNotMasqueradeAsNoUpdates() async {
        for (client, expected) in [
            (client(status: 429), UpdateCheckError.rateLimited),
            (client(status: 403, headers: ["X-RateLimit-Remaining": "0"]), .rateLimited),
            (client(status: 503), .server(503)),
            (client(body: "not json"), .response),
            (client(body: release(tag: "latest")), .version),
            (client(body: release(url: "https://example.com/download")), .response),
            (GitHubReleaseClient(repository: UpdateRepository("legjs/MiaoRight")!, load: { _ in throw URLError(.notConnectedToInternet) }), .network)
        ] {
            do { _ = try await client.latestRelease(); XCTFail("Expected \(expected)") }
            catch { XCTAssertEqual(error as? UpdateCheckError, expected) }
        }
    }

    func testReleaseLinksStayInConfiguredRepository() throws {
        let repository = try XCTUnwrap(UpdateRepository("legjs/MiaoRight"))
        XCTAssertTrue(repository.contains(URL(string: "https://github.com/legjs/MiaoRight/releases/tag/v1.1.0")!))
        for url in ["http://github.com/legjs/MiaoRight/releases/tag/v1", "https://github.com/other/repo/releases/tag/v1", "https://github.com/legjs/MiaoRight-evil/releases/tag/v1", "https://github.com@evil.example/legjs/MiaoRight/releases/tag/v1"] {
            XCTAssertFalse(repository.contains(URL(string: url)!))
        }
        XCTAssertNil(UpdateRepository("legjs/../other"))
        XCTAssertNil(UpdateRepository("legjs/"))
    }
}
