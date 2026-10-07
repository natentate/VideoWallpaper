import Foundation

enum VideoSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case pexels
    case pixabay
    case nasa

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pexels: return "Pexels"
        case .pixabay: return "Pixabay"
        case .nasa: return "NASA"
        }
    }

    var requiresAPIKey: Bool { self != .nasa }

    var tagline: String {
        switch self {
        case .pexels: return "Huge library of free 4K stock video. Free API key."
        case .pixabay: return "Free stock video, lots of loops and animations. Free API key."
        case .nasa: return "NASA Image & Video Library: launches, Earth from orbit, space. No key needed."
        }
    }

    var homepage: URL {
        switch self {
        case .pexels: return URL(string: "https://www.pexels.com/videos/")!
        case .pixabay: return URL(string: "https://pixabay.com/videos/")!
        case .nasa: return URL(string: "https://images.nasa.gov")!
        }
    }

    var apiKeyURL: URL? {
        switch self {
        case .pexels: return URL(string: "https://www.pexels.com/api/new/")
        case .pixabay: return URL(string: "https://pixabay.com/api/docs/")
        case .nasa: return nil
        }
    }

    var attribution: String {
        switch self {
        case .pexels: return "Videos provided by Pexels"
        case .pixabay: return "Videos provided by Pixabay"
        case .nasa: return "Courtesy of NASA"
        }
    }
}

struct RemoteVideoFile: Identifiable, Hashable, Sendable {
    var id: String { url.absoluteString }
    let url: URL
    let width: Int?
    let height: Int?
    let fps: Double?
    let sizeBytes: Int64?
    /// Used when dimensions are unknown (NASA renditions).
    let label: String?

    var pixelCount: Int { (width ?? 0) * (height ?? 0) }

    var displayName: String {
        var parts: [String] = []
        if let width, let height {
            parts.append("\(Wallpaper.resolutionLabel(width: width, height: height)) · \(width)×\(height)")
        } else if let label {
            parts.append(label)
        }
        if let fps, fps > 0 {
            parts.append("\(Int(fps.rounded())) fps")
        }
        if let sizeBytes, sizeBytes > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file))
        }
        return parts.isEmpty ? url.lastPathComponent : parts.joined(separator: " · ")
    }
}

struct RemoteVideo: Identifiable, Hashable, Sendable {
    /// "<source>:<id>"
    let id: String
    let source: VideoSource
    let title: String
    let author: String?
    let pageURL: URL?
    let thumbnailURL: URL?
    let duration: Double?
    /// Best quality first. Empty for NASA until `manifestURL` is resolved.
    var files: [RemoteVideoFile]
    let manifestURL: URL?

    var bestFile: RemoteVideoFile? { files.first }

    var resolutionLabel: String? {
        guard let file = files.first(where: { $0.width != nil }), let width = file.width, let height = file.height else { return nil }
        return Wallpaper.resolutionLabel(width: width, height: height)
    }

    /// A small rendition suitable for streaming in the preview sheet.
    var previewFile: RemoteVideoFile? {
        let sized = files.filter { ($0.width ?? 0) >= 640 }.sorted { $0.pixelCount < $1.pixelCount }
        if let candidate = sized.first(where: { ($0.width ?? 0) >= 960 }) ?? sized.first {
            return candidate
        }
        let order = ["Mobile", "Small", "Medium", "Large", "Preview", "Original"]
        for label in order {
            if let file = files.first(where: { $0.label == label }) { return file }
        }
        return files.last
    }

    /// Picks the download rendition for the user's quality preference.
    func preferredFile(for quality: DownloadQuality) -> RemoteVideoFile? {
        guard !files.isEmpty else { return nil }
        if files.allSatisfy({ $0.width == nil }) {
            // NASA: originals can be multi-gigabyte ProRes; default to the large rendition.
            let order = quality == .best ? ["Large", "Original", "Medium"] : ["Large", "Medium", "Original"]
            for label in order {
                if let file = files.first(where: { $0.label == label }) { return file }
            }
            return files.first
        }
        guard let maxWidth = quality.maxWidth else { return files.first }
        return files.first { ($0.width ?? 0) <= maxWidth } ?? files.last
    }
}

struct SearchPage: Sendable {
    let videos: [RemoteVideo]
    let hasMore: Bool
}

enum ProviderError: LocalizedError {
    case missingAPIKey(VideoSource)
    case http(Int, VideoSource)
    case invalidResponse
    case noDownloadableFile

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let source):
            return "Add a free \(source.title) API key in Settings to browse \(source.title)."
        case .http(let status, let source):
            switch status {
            case 400, 401, 403: return "\(source.title) rejected the request (HTTP \(status)). Check your API key in Settings."
            case 429: return "\(source.title) rate limit reached. Try again in a few minutes."
            default: return "\(source.title) returned an error (HTTP \(status))."
            }
        case .invalidResponse:
            return "The server sent an unexpected response."
        case .noDownloadableFile:
            return "No downloadable video file was found for this item."
        }
    }
}

protocol VideoSearchProvider: Sendable {
    func search(query: String, page: Int, only4K: Bool) async throws -> SearchPage
}

enum HTTPClient {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.httpAdditionalHeaders = ["User-Agent": "VideoWallpaper/1.0 (macOS)"]
        return URLSession(configuration: configuration)
    }()

    static func getJSON<T: Decodable>(_ type: T.Type, from url: URL, headers: [String: String] = [:], source: VideoSource) async throws -> T {
        var request = URLRequest(url: url)
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ProviderError.http(http.statusCode, source) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Normalises URLs from APIs that return http:// links or unescaped spaces.
    static func url(from string: String?) -> URL? {
        guard var string = string?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else { return nil }
        if string.hasPrefix("http://") {
            string = "https://" + string.dropFirst("http://".count)
        }
        string = string.replacingOccurrences(of: " ", with: "%20")
        return URL(string: string)
    }
}
