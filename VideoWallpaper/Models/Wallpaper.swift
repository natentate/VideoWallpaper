import Foundation

struct Wallpaper: Identifiable, Codable, Hashable, Sendable {
    enum Origin: String, Codable, Sendable, CaseIterable {
        case imported
        case downloaded
        case generated

        var label: String {
            switch self {
            case .imported: return "Imported"
            case .downloaded: return "Downloaded"
            case .generated: return "Generated"
            }
        }
    }

    var id: UUID
    var name: String
    /// File name inside `AppPaths.videos`.
    var fileName: String
    var origin: Origin
    var provider: String?
    var author: String?
    var pageURL: URL?
    /// "<source>:<id>" for downloaded items, used to detect duplicates.
    var remoteID: String?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var duration: Double?
    var fileSize: Int64?
    var isFavorite: Bool
    var dateAdded: Date

    init(
        id: UUID = UUID(),
        name: String,
        fileName: String,
        origin: Origin,
        provider: String? = nil,
        author: String? = nil,
        pageURL: URL? = nil,
        remoteID: String? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        duration: Double? = nil,
        fileSize: Int64? = nil,
        isFavorite: Bool = false,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.origin = origin
        self.provider = provider
        self.author = author
        self.pageURL = pageURL
        self.remoteID = remoteID
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.fileSize = fileSize
        self.isFavorite = isFavorite
        self.dateAdded = dateAdded
    }

    var fileURL: URL { AppPaths.videos.appendingPathComponent(fileName) }
    var thumbnailURL: URL { AppPaths.thumbnails.appendingPathComponent("\(id.uuidString).jpg") }
    var stillURL: URL { AppPaths.stills.appendingPathComponent("\(id.uuidString).jpg") }

    var resolutionLabel: String? {
        guard let width = pixelWidth, let height = pixelHeight else { return nil }
        return Self.resolutionLabel(width: width, height: height)
    }

    var durationLabel: String? {
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        return Self.durationLabel(duration)
    }

    var sourceLabel: String {
        provider ?? origin.label
    }

    static func resolutionLabel(width: Int, height: Int) -> String {
        let long = max(width, height)
        let short = min(width, height)
        if long >= 7680 || short >= 4320 { return "8K" }
        if long >= 5120 || short >= 2880 { return "5K" }
        if long >= 3840 || short >= 2160 { return "4K" }
        if long >= 2560 || short >= 1440 { return "1440p" }
        if long >= 1920 || short >= 1080 { return "1080p" }
        if long >= 1280 || short >= 720 { return "720p" }
        return "\(short)p"
    }

    static func durationLabel(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
