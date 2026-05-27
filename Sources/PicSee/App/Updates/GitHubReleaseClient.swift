import Foundation

struct GitHubRelease: Equatable {
    let tagName: String
    let version: AppVersion
    let dmgURL: URL
}

enum GitHubReleaseClientError: Error {
    case invalidReleaseTag(String)
    case invalidHTTPStatus(Int)
}

struct GitHubReleaseClient {
    static let latestReleaseURL = URL(string: "https://github.com/houleixx/PicSee/releases/latest")!

    private struct ReleasePayload: Decodable {
        let tagName: String

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
        }
    }

    func fetchLatestRelease() async throws -> GitHubRelease {
        let (data, response) = try await URLSession.shared.data(for: Self.makeLatestReleaseRequest())
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw GitHubReleaseClientError.invalidHTTPStatus(httpResponse.statusCode)
        }
        if let finalURL = response.url {
            return try Self.release(fromFinalURL: finalURL)
        }
        return try Self.decodeRelease(from: data)
    }

    static func makeLatestReleaseRequest() -> URLRequest {
        var request = URLRequest(url: latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("PicSee", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return request
    }

    static func release(fromFinalURL url: URL) throws -> GitHubRelease {
        let tagName = url.lastPathComponent
        guard let version = AppVersion(tagName), tagName.lowercased().hasPrefix("v") else {
            throw GitHubReleaseClientError.invalidReleaseTag(tagName)
        }

        return GitHubRelease(
            tagName: tagName,
            version: version,
            dmgURL: dmgDownloadURL(for: version)
        )
    }

    static func decodeRelease(from data: Data) throws -> GitHubRelease {
        let payload = try JSONDecoder().decode(ReleasePayload.self, from: data)
        guard let version = AppVersion(payload.tagName) else {
            throw GitHubReleaseClientError.invalidReleaseTag(payload.tagName)
        }

        return GitHubRelease(
            tagName: payload.tagName,
            version: version,
            dmgURL: dmgDownloadURL(for: version)
        )
    }

    static func dmgDownloadURL(for version: AppVersion) -> URL {
        URL(string: "https://github.com/houleixx/PicSee/releases/download/v\(version.displayString)/PicSee-\(version.displayString).dmg")!
    }
}
