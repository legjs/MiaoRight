import Foundation
import XCTest
@testable import MiaoRightKit

final class GitHubAtomReleaseClientTests: XCTestCase {
    func testAtomFallbackSelectsLatestStableReleaseAndLoadsNotesAndAssets() async throws {
        let repository = try XCTUnwrap(UpdateRepository("legjs/MiaoRight"))
        let atom = """
        <feed>
          <entry>
            <id>tag:github.com,2008:Repository/1/v2.0.0-beta.1</id>
            <updated>2026-11-25T10:00:00Z</updated>
            <link rel="alternate" type="text/html" href="https://github.com/legjs/MiaoRight/releases/tag/v2.0.0-beta.1"/>
            <title>MiaoRight 2.0.0 beta</title>
          </entry>
          <entry>
            <id>tag:github.com,2008:Repository/1/v0.1.4</id>
            <updated>2026-11-25T11:00:00Z</updated>
            <link rel="alternate" type="text/html" href="https://github.com/legjs/MiaoRight/releases/tag/v0.1.4"/>
            <title>MiaoRight 0.1.4</title>
          </entry>
        </feed>
        """
        let notes = "## 中文\n\n### 新增\n\n- 新版本。\n"
        let client = GitHubAtomReleaseClient(repository: repository, load: { request in
            let url = try XCTUnwrap(request.url)
            if url.absoluteString.hasSuffix("/releases.atom") {
                return (Data(atom.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!) 
            }
            if url.host == "raw.githubusercontent.com" {
                return (Data(notes.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!) 
            }
            XCTAssertEqual(request.httpMethod, "HEAD")
            return (Data(), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": "1234"])!)
        })

        let loaded = try await client.latestRelease()
        let release = try XCTUnwrap(loaded)
        XCTAssertEqual(release.tagName, "v0.1.4")
        XCTAssertEqual(release.name, "MiaoRight 0.1.4")
        XCTAssertEqual(release.notes, notes)
        XCTAssertEqual(release.assets.count, 2)
        XCTAssertTrue(release.assets.allSatisfy { $0.size == 1234 })
        XCTAssertNotNil(release.installer(for: .arm64, repository: repository))
        XCTAssertNotNil(release.installer(for: .x86_64, repository: repository))
    }
}
