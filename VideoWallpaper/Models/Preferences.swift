import AVFoundation
import Foundation

enum VideoScaling: String, CaseIterable, Identifiable, Sendable {
    case fill
    case fit
    case stretch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: return "Fill Screen"
        case .fit: return "Fit to Screen"
        case .stretch: return "Stretch"
        }
    }

    var gravity: AVLayerVideoGravity {
        switch self {
        case .fill: return .resizeAspectFill
        case .fit: return .resizeAspect
        case .stretch: return .resize
        }
    }
}

enum RotationInterval: String, CaseIterable, Identifiable, Sendable {
    case off
    case minutes15
    case minutes30
    case hour1
    case hours3
    case daily

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Never"
        case .minutes15: return "Every 15 minutes"
        case .minutes30: return "Every 30 minutes"
        case .hour1: return "Every hour"
        case .hours3: return "Every 3 hours"
        case .daily: return "Every day"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .off: return nil
        case .minutes15: return 15 * 60
        case .minutes30: return 30 * 60
        case .hour1: return 60 * 60
        case .hours3: return 3 * 60 * 60
        case .daily: return 24 * 60 * 60
        }
    }
}

enum RotationSource: String, CaseIterable, Identifiable, Sendable {
    case all
    case favorites

    var id: String { rawValue }
    var title: String { self == .all ? "All Wallpapers" : "Favorites" }
}

enum DownloadQuality: String, CaseIterable, Identifiable, Sendable {
    case best
    case uhd
    case qhd
    case fhd

    var id: String { rawValue }

    var title: String {
        switch self {
        case .best: return "Best Available"
        case .uhd: return "Up to 4K"
        case .qhd: return "Up to 1440p"
        case .fhd: return "Up to 1080p"
        }
    }

    /// Largest acceptable width, or nil for no limit.
    var maxWidth: Int? {
        switch self {
        case .best: return nil
        case .uhd: return 4096
        case .qhd: return 2560
        case .fhd: return 1920
        }
    }
}

/// User preferences, persisted in UserDefaults.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let scaling = "scaling"
        static let pauseOnBattery = "pauseOnBattery"
        static let pauseInLowPowerMode = "pauseInLowPowerMode"
        static let pauseWhenCovered = "pauseWhenCovered"
        static let crossfade = "crossfade"
        static let syncDesktopPicture = "syncDesktopPicture"
        static let hideDockIconWhenClosed = "hideDockIconWhenClosed"
        static let rotationInterval = "rotationInterval"
        static let rotationSource = "rotationSource"
        static let pexelsAPIKey = "pexelsAPIKey"
        static let pixabayAPIKey = "pixabayAPIKey"
        static let downloadQuality = "downloadQuality"
        static let catalogURL = "catalogURL"
    }

    static let defaultCatalogURL = "https://raw.githubusercontent.com/natentate/VideoWallpaper/main/Catalog/catalog.json"

    private let defaults = UserDefaults.standard

    @Published var scaling: VideoScaling { didSet { defaults.set(scaling.rawValue, forKey: Key.scaling) } }
    @Published var pauseOnBattery: Bool { didSet { defaults.set(pauseOnBattery, forKey: Key.pauseOnBattery) } }
    @Published var pauseInLowPowerMode: Bool { didSet { defaults.set(pauseInLowPowerMode, forKey: Key.pauseInLowPowerMode) } }
    @Published var pauseWhenCovered: Bool { didSet { defaults.set(pauseWhenCovered, forKey: Key.pauseWhenCovered) } }
    @Published var crossfade: Bool { didSet { defaults.set(crossfade, forKey: Key.crossfade) } }
    @Published var syncDesktopPicture: Bool { didSet { defaults.set(syncDesktopPicture, forKey: Key.syncDesktopPicture) } }
    @Published var hideDockIconWhenClosed: Bool { didSet { defaults.set(hideDockIconWhenClosed, forKey: Key.hideDockIconWhenClosed) } }
    @Published var rotationInterval: RotationInterval { didSet { defaults.set(rotationInterval.rawValue, forKey: Key.rotationInterval) } }
    @Published var rotationSource: RotationSource { didSet { defaults.set(rotationSource.rawValue, forKey: Key.rotationSource) } }
    @Published var pexelsAPIKey: String { didSet { defaults.set(pexelsAPIKey, forKey: Key.pexelsAPIKey) } }
    @Published var pixabayAPIKey: String { didSet { defaults.set(pixabayAPIKey, forKey: Key.pixabayAPIKey) } }
    @Published var downloadQuality: DownloadQuality { didSet { defaults.set(downloadQuality.rawValue, forKey: Key.downloadQuality) } }
    @Published var catalogURL: String { didSet { defaults.set(catalogURL, forKey: Key.catalogURL) } }

    private init() {
        defaults.register(defaults: [
            Key.scaling: VideoScaling.fill.rawValue,
            Key.pauseOnBattery: false,
            Key.pauseInLowPowerMode: true,
            Key.pauseWhenCovered: true,
            Key.crossfade: true,
            Key.syncDesktopPicture: false,
            Key.hideDockIconWhenClosed: true,
            Key.rotationInterval: RotationInterval.off.rawValue,
            Key.rotationSource: RotationSource.all.rawValue,
            Key.pexelsAPIKey: "",
            Key.pixabayAPIKey: "",
            Key.downloadQuality: DownloadQuality.best.rawValue,
            Key.catalogURL: Self.defaultCatalogURL,
        ])

        scaling = VideoScaling(rawValue: defaults.string(forKey: Key.scaling) ?? "") ?? .fill
        pauseOnBattery = defaults.bool(forKey: Key.pauseOnBattery)
        pauseInLowPowerMode = defaults.bool(forKey: Key.pauseInLowPowerMode)
        pauseWhenCovered = defaults.bool(forKey: Key.pauseWhenCovered)
        crossfade = defaults.bool(forKey: Key.crossfade)
        syncDesktopPicture = defaults.bool(forKey: Key.syncDesktopPicture)
        hideDockIconWhenClosed = defaults.bool(forKey: Key.hideDockIconWhenClosed)
        rotationInterval = RotationInterval(rawValue: defaults.string(forKey: Key.rotationInterval) ?? "") ?? .off
        rotationSource = RotationSource(rawValue: defaults.string(forKey: Key.rotationSource) ?? "") ?? .all
        pexelsAPIKey = defaults.string(forKey: Key.pexelsAPIKey) ?? ""
        pixabayAPIKey = defaults.string(forKey: Key.pixabayAPIKey) ?? ""
        downloadQuality = DownloadQuality(rawValue: defaults.string(forKey: Key.downloadQuality) ?? "") ?? .best
        catalogURL = defaults.string(forKey: Key.catalogURL) ?? Self.defaultCatalogURL
    }

    func apiKey(for source: VideoSource) -> String {
        switch source {
        case .pexels: return pexelsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .pixabay: return pixabayAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .nasa: return ""
        }
    }

    func isConfigured(_ source: VideoSource) -> Bool {
        !source.requiresAPIKey || !apiKey(for: source).isEmpty
    }
}
