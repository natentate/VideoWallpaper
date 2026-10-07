import Foundation

// MARK: - Pexels (https://www.pexels.com/api/documentation/#videos)

struct PexelsProvider: VideoSearchProvider {
    let apiKey: String

    func search(query: String, page: Int, only4K: Bool) async throws -> SearchPage {
        guard !apiKey.isEmpty else { throw ProviderError.missingAPIKey(.pexels) }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var components: URLComponents
        if trimmed.isEmpty {
            components = URLComponents(string: "https://api.pexels.com/videos/popular")!
            components.queryItems = [
                URLQueryItem(name: "min_width", value: only4K ? "3840" : "1920"),
            ]
        } else {
            components = URLComponents(string: "https://api.pexels.com/videos/search")!
            components.queryItems = [
                URLQueryItem(name: "query", value: trimmed),
                URLQueryItem(name: "orientation", value: "landscape"),
                URLQueryItem(name: "size", value: only4K ? "large" : "medium"),
            ]
        }
        components.queryItems? += [
            URLQueryItem(name: "per_page", value: "30"),
            URLQueryItem(name: "page", value: String(page)),
        ]
        guard let url = components.url else { throw ProviderError.invalidResponse }
        let data = try await HTTPClient.getData(from: url, headers: ["Authorization": apiKey], source: .pexels)
        return try Self.page(from: data)
    }

    /// Parses a /videos/search or /videos/popular response.
    static func page(from data: Data) throws -> SearchPage {
        let response = try JSONDecoder().decode(PexelsResponse.self, from: data)
        let videos = (response.videos ?? []).compactMap(Self.map)
        return SearchPage(videos: videos, hasMore: response.nextPage != nil)
    }

    private static func map(_ video: PexelsVideo) -> RemoteVideo? {
        let files = (video.videoFiles ?? [])
            .filter { file in
                let type = (file.fileType ?? "video/mp4").lowercased()
                return file.width != nil && (type.contains("mp4") || type.contains("quicktime")) && file.quality?.lowercased() != "hls"
            }
            .compactMap { file -> RemoteVideoFile? in
                guard let url = HTTPClient.url(from: file.link) else { return nil }
                return RemoteVideoFile(url: url, width: file.width, height: file.height, fps: file.fps, sizeBytes: file.size, label: file.quality?.uppercased())
            }
            .sorted { $0.pixelCount > $1.pixelCount }
        guard !files.isEmpty else { return nil }
        let pageURL = HTTPClient.url(from: video.url)
        return RemoteVideo(
            id: "pexels:\(video.id)",
            source: .pexels,
            title: Self.title(fromPage: pageURL) ?? "Pexels Video \(video.id)",
            author: video.user?.name,
            pageURL: pageURL,
            thumbnailURL: HTTPClient.url(from: video.image),
            duration: video.duration,
            files: files,
            manifestURL: nil
        )
    }

    /// "https://www.pexels.com/video/rain-drops-on-a-window-3645365/" → "Rain drops on a window"
    private static func title(fromPage url: URL?) -> String? {
        guard let slug = url?.pathComponents.last(where: { $0 != "/" }) else { return nil }
        var words = slug.split(separator: "-").map(String.init)
        if let last = words.last, Int(last) != nil { words.removeLast() }
        guard !words.isEmpty else { return nil }
        let sentence = words.joined(separator: " ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }
}

private struct PexelsResponse: Decodable {
    let videos: [PexelsVideo]?
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case videos
        case nextPage = "next_page"
    }
}

private struct PexelsVideo: Decodable {
    let id: Int
    let url: String?
    let image: String?
    let duration: Double?
    let user: PexelsUser?
    let videoFiles: [PexelsFile]?

    enum CodingKeys: String, CodingKey {
        case id, url, image, duration, user
        case videoFiles = "video_files"
    }
}

private struct PexelsUser: Decodable {
    let name: String?
}

private struct PexelsFile: Decodable {
    let quality: String?
    let fileType: String?
    let width: Int?
    let height: Int?
    let fps: Double?
    let link: String?
    let size: Int64?

    enum CodingKeys: String, CodingKey {
        case quality, width, height, fps, link, size
        case fileType = "file_type"
    }
}

// MARK: - Pixabay (https://pixabay.com/api/docs/#api_search_videos)

struct PixabayProvider: VideoSearchProvider {
    let apiKey: String
    private let perPage = 30

    func search(query: String, page: Int, only4K: Bool) async throws -> SearchPage {
        guard !apiKey.isEmpty else { throw ProviderError.missingAPIKey(.pixabay) }
        var components = URLComponents(string: "https://pixabay.com/api/videos/")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "q", value: String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))),
            URLQueryItem(name: "video_type", value: "all"),
            URLQueryItem(name: "safesearch", value: "true"),
            URLQueryItem(name: "order", value: "popular"),
            URLQueryItem(name: "min_width", value: only4K ? "3840" : "1920"),
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "page", value: String(page)),
        ]
        guard let url = components.url else { throw ProviderError.invalidResponse }
        let data = try await HTTPClient.getData(from: url, source: .pixabay)
        return try Self.page(from: data, page: page, perPage: perPage)
    }

    /// Parses a /api/videos/ response.
    static func page(from data: Data, page: Int, perPage: Int) throws -> SearchPage {
        let response = try JSONDecoder().decode(PixabayResponse.self, from: data)
        let videos = (response.hits ?? []).compactMap(Self.map)
        let totalHits = response.totalHits ?? 0
        return SearchPage(videos: videos, hasMore: page * perPage < totalHits)
    }

    private static func map(_ hit: PixabayHit) -> RemoteVideo? {
        let renditions = hit.videos ?? [:]
        let files = ["large", "medium", "small", "tiny"]
            .compactMap { renditions[$0] }
            .compactMap { file -> RemoteVideoFile? in
                guard let url = HTTPClient.url(from: file.url), (file.width ?? 0) > 0 else { return nil }
                return RemoteVideoFile(url: url, width: file.width, height: file.height, fps: nil, sizeBytes: file.size, label: nil)
            }
            .sorted { $0.pixelCount > $1.pixelCount }
        guard !files.isEmpty else { return nil }
        let thumbnail = renditions["medium"]?.thumbnail ?? renditions["small"]?.thumbnail ?? renditions["large"]?.thumbnail
        let tags = (hit.tags ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let title = tags.prefix(3).joined(separator: ", ")
        return RemoteVideo(
            id: "pixabay:\(hit.id)",
            source: .pixabay,
            title: title.isEmpty ? "Pixabay Video \(hit.id)" : title.prefix(1).uppercased() + title.dropFirst(),
            author: hit.user,
            pageURL: HTTPClient.url(from: hit.pageURL),
            thumbnailURL: HTTPClient.url(from: thumbnail),
            duration: hit.duration,
            files: files,
            manifestURL: nil
        )
    }
}

private struct PixabayResponse: Decodable {
    let totalHits: Int?
    let hits: [PixabayHit]?
}

private struct PixabayHit: Decodable {
    let id: Int
    let pageURL: String?
    let tags: String?
    let duration: Double?
    let user: String?
    let videos: [String: PixabayFile]?
}

private struct PixabayFile: Decodable {
    let url: String?
    let width: Int?
    let height: Int?
    let size: Int64?
    let thumbnail: String?
}

// MARK: - NASA Image and Video Library (https://images.nasa.gov/docs/images.nasa.gov_api_docs.pdf)

struct NASAProvider: VideoSearchProvider {
    private let pageSize = 30

    func search(query: String, page: Int, only4K: Bool) async throws -> SearchPage {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents(string: "https://images-api.nasa.gov/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed.isEmpty ? "earth from space" : trimmed),
            URLQueryItem(name: "media_type", value: "video"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(pageSize)),
        ]
        guard let url = components.url else { throw ProviderError.invalidResponse }
        let response = try await HTTPClient.getJSON(NASASearchResponse.self, from: url, source: .nasa)
        let videos = response.collection.items.compactMap { item -> RemoteVideo? in
            guard let data = item.data.first else { return nil }
            let thumbnail = item.links?.first(where: { $0.render == "image" || $0.rel == "preview" })?.href
            let escapedID = data.nasaID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? data.nasaID
            return RemoteVideo(
                id: "nasa:\(data.nasaID)",
                source: .nasa,
                title: data.title ?? data.nasaID,
                author: data.center.map { "NASA \($0)" } ?? "NASA",
                pageURL: URL(string: "https://images.nasa.gov/details/\(escapedID)"),
                thumbnailURL: HTTPClient.url(from: thumbnail),
                duration: nil,
                files: [],
                manifestURL: HTTPClient.url(from: item.href)
            )
        }
        let hasNext = response.collection.links?.contains { $0.rel == "next" } ?? false
        return SearchPage(videos: videos, hasMore: hasNext)
    }

    /// NASA lists renditions in a per-item manifest (an array of URLs).
    static func resolveFiles(manifest: URL) async throws -> [RemoteVideoFile] {
        let entries = try await HTTPClient.getJSON([String].self, from: manifest, source: .nasa)
        let ranked: [(suffix: String, label: String)] = [
            ("~orig", "Original"), ("~large", "Large"), ("~medium", "Medium"),
            ("~small", "Small"), ("~mobile", "Mobile"), ("~preview", "Preview"),
        ]
        var files: [(rank: Int, file: RemoteVideoFile)] = []
        for entry in entries {
            guard let url = HTTPClient.url(from: entry),
                  VideoInspector.supportedExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            let match = ranked.firstIndex { name.hasSuffix($0.suffix) }
            let label = match.map { ranked[$0].label } ?? url.lastPathComponent
            files.append((match ?? ranked.count, RemoteVideoFile(url: url, width: nil, height: nil, fps: nil, sizeBytes: nil, label: label)))
        }
        return files.sorted { $0.rank < $1.rank }.map { $0.file }
    }
}

private struct NASASearchResponse: Decodable {
    let collection: Collection

    struct Collection: Decodable {
        let items: [Item]
        let links: [Link]?
    }

    struct Item: Decodable {
        let href: String?
        let data: [Entry]
        let links: [Link]?
    }

    struct Entry: Decodable {
        let nasaID: String
        let title: String?
        let center: String?

        enum CodingKeys: String, CodingKey {
            case nasaID = "nasa_id"
            case title, center
        }
    }

    struct Link: Decodable {
        let href: String?
        let rel: String?
        let render: String?
    }
}
