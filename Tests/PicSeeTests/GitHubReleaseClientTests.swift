import XCTest
@testable import PicSee

final class GitHubReleaseClientTests: XCTestCase {
    func testDecodesLatestReleaseTag() throws {
        let data = Data(#"{"tag_name":"v0.2.13"}"#.utf8)

        let release = try GitHubReleaseClient.decodeRelease(from: data)

        XCTAssertEqual(release.tagName, "v0.2.13")
        XCTAssertEqual(release.version.displayString, "0.2.13")
    }

    func testBuildsDeterministicDMGDownloadURL() throws {
        let version = try XCTUnwrap(AppVersion("0.2.13"))

        let url = GitHubReleaseClient.dmgDownloadURL(for: version)

        XCTAssertEqual(
            url.absoluteString,
            "https://github.com/houleixx/PicSee/releases/download/v0.2.13/PicSee-0.2.13.dmg"
        )
    }

    func testRejectsInvalidReleaseTag() {
        let data = Data(#"{"tag_name":"latest"}"#.utf8)

        XCTAssertThrowsError(try GitHubReleaseClient.decodeRelease(from: data))
    }

    func testBuildsLatestReleaseRedirectRequestWithoutUsingGitHubAPI() {
        let request = GitHubReleaseClient.makeLatestReleaseRequest()

        XCTAssertEqual(request.url, GitHubReleaseClient.latestReleaseURL)
        XCTAssertEqual(request.url?.absoluteString, "https://github.com/houleixx/PicSee/releases/latest")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "PicSee")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
    }

    func testParsesLatestReleaseFromRedirectedTagURL() throws {
        let responseURL = try XCTUnwrap(URL(string: "https://github.com/houleixx/PicSee/releases/tag/v0.2.13"))

        let release = try GitHubReleaseClient.release(fromFinalURL: responseURL)

        XCTAssertEqual(release.tagName, "v0.2.13")
        XCTAssertEqual(release.version.displayString, "0.2.13")
        XCTAssertEqual(
            release.dmgURL.absoluteString,
            "https://github.com/houleixx/PicSee/releases/download/v0.2.13/PicSee-0.2.13.dmg"
        )
    }
}
