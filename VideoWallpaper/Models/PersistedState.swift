import Foundation

/// A named set of wallpapers that is shown while a macOS Focus is on.
struct FocusProfile: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var symbol: String
    /// Wallpaper for every display (unless overridden in `perDisplay`).
    var wallpaperID: UUID?
    /// Optional per-display overrides, keyed by `DisplayInfo.id`.
    var perDisplay: [String: UUID]
    /// Pause video playback while this Focus is on (e.g. Sleep).
    var pausesPlayback: Bool

    init(id: UUID = UUID(), name: String, symbol: String, wallpaperID: UUID? = nil, perDisplay: [String: UUID] = [:], pausesPlayback: Bool = false) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.wallpaperID = wallpaperID
        self.perDisplay = perDisplay
        self.pausesPlayback = pausesPlayback
    }

    var hasAssignment: Bool { wallpaperID != nil || !perDisplay.isEmpty }

    struct Preset: Hashable, Sendable {
        let name: String
        let symbol: String
    }

    static let presets: [Preset] = [
        Preset(name: "Do Not Disturb", symbol: "moon.fill"),
        Preset(name: "Work", symbol: "briefcase.fill"),
        Preset(name: "Personal", symbol: "person.fill"),
        Preset(name: "Sleep", symbol: "bed.double.fill"),
        Preset(name: "Reduce Interruptions", symbol: "bell.slash.fill"),
        Preset(name: "Driving", symbol: "car.fill"),
        Preset(name: "Fitness", symbol: "figure.run"),
        Preset(name: "Gaming", symbol: "gamecontroller.fill"),
        Preset(name: "Mindfulness", symbol: "brain.head.profile"),
        Preset(name: "Reading", symbol: "book.fill"),
    ]

    static var defaultProfiles: [FocusProfile] {
        ["Do Not Disturb", "Work", "Personal", "Sleep"].compactMap { name in
            presets.first { $0.name == name }.map { FocusProfile(name: $0.name, symbol: $0.symbol) }
        }
    }
}

/// Records that a Focus wallpaper is currently active, and what turned it on.
struct FocusActivation: Codable, Hashable, Sendable {
    enum Source: String, Codable, Sendable {
        /// Shortcuts action, URL scheme or the app's own UI.
        case shortcut
        /// System Settings › Focus › Focus Filters.
        case focusFilter
    }

    var profileID: UUID?
    /// Used when a Focus Filter picks a wallpaper directly instead of a profile.
    var wallpaperID: UUID?
    var source: Source
    var date: Date
}

struct PersistedState: Codable, Sendable {
    var defaultWallpaperID: UUID?
    var perDisplayWallpaper: [String: UUID] = [:]
    var sameOnAllDisplays = true
    var focusProfiles: [FocusProfile] = FocusProfile.defaultProfiles
    var activations: [FocusActivation] = []
    var isPaused = false
    var hasLaunchedBefore = false

    init() {}

    enum CodingKeys: String, CodingKey {
        case defaultWallpaperID, perDisplayWallpaper, sameOnAllDisplays, focusProfiles, activations, isPaused, hasLaunchedBefore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultWallpaperID = try container.decodeIfPresent(UUID.self, forKey: .defaultWallpaperID)
        perDisplayWallpaper = try container.decodeIfPresent([String: UUID].self, forKey: .perDisplayWallpaper) ?? [:]
        sameOnAllDisplays = try container.decodeIfPresent(Bool.self, forKey: .sameOnAllDisplays) ?? true
        focusProfiles = try container.decodeIfPresent([FocusProfile].self, forKey: .focusProfiles) ?? FocusProfile.defaultProfiles
        activations = try container.decodeIfPresent([FocusActivation].self, forKey: .activations) ?? []
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        hasLaunchedBefore = try container.decodeIfPresent(Bool.self, forKey: .hasLaunchedBefore) ?? false
    }

    static func load() -> PersistedState {
        guard let data = try? Data(contentsOf: AppPaths.stateFile),
              let state = try? JSONDecoder.iso8601.decode(PersistedState.self, from: data) else {
            return PersistedState()
        }
        return state
    }

    func save() {
        do {
            let data = try JSONEncoder.pretty.encode(self)
            try data.write(to: AppPaths.stateFile, options: .atomic)
        } catch {
            NSLog("VideoWallpaper: failed to save state: \(error)")
        }
    }
}
