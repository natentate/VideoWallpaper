import Foundation

/// On-disk layout: ~/Library/Application Support/VideoWallpaper
enum AppPaths {
    static let root: URL = {
        // Lets CI and the self-test run against an isolated data directory.
        if let override = ProcessInfo.processInfo.environment["VIDEOWALLPAPER_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("VideoWallpaper", isDirectory: true)
    }()

    static let videos = root.appendingPathComponent("Videos", isDirectory: true)
    static let thumbnails = root.appendingPathComponent("Thumbnails", isDirectory: true)
    static let stills = root.appendingPathComponent("Stills", isDirectory: true)
    static let staging = root.appendingPathComponent("Staging", isDirectory: true)

    static let libraryFile = root.appendingPathComponent("library.json")
    static let stateFile = root.appendingPathComponent("state.json")
    static let catalogCacheFile = root.appendingPathComponent("catalog-cache.json")

    static func prepare() {
        for directory in [root, videos, thumbnails, stills, staging] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        // Anything left in staging is from an interrupted download or render.
        if let leftovers = try? FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) {
            leftovers.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
