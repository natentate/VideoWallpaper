import AppIntents
import Foundation

// MARK: - Entities

struct WallpaperEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Video Wallpaper"
    static var defaultQuery = WallpaperEntityQuery()

    let id: UUID
    let name: String
    let detail: String

    init(_ wallpaper: Wallpaper) {
        id = wallpaper.id
        name = wallpaper.name
        detail = [wallpaper.sourceLabel, wallpaper.resolutionLabel].compactMap { $0 }.joined(separator: " · ")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
    }
}

struct WallpaperEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [WallpaperEntity] {
        LibraryStore.readFromDisk()
            .filter { identifiers.contains($0.id) }
            .map(WallpaperEntity.init)
    }

    func entities(matching string: String) async throws -> [WallpaperEntity] {
        LibraryStore.readFromDisk()
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(WallpaperEntity.init)
    }

    func suggestedEntities() async throws -> [WallpaperEntity] {
        LibraryStore.readFromDisk()
            .sorted { $0.dateAdded > $1.dateAdded }
            .map(WallpaperEntity.init)
    }
}

/// A Focus profile defined in the app (Focus Modes screen).
struct FocusProfileEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Focus Wallpaper"
    static var defaultQuery = FocusProfileEntityQuery()

    let id: UUID
    let name: String

    init(_ profile: FocusProfile) {
        id = profile.id
        name = profile.name
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct FocusProfileEntityQuery: EntityStringQuery {
    private func profiles() -> [FocusProfile] {
        PersistedState.load().focusProfiles
    }

    func entities(for identifiers: [UUID]) async throws -> [FocusProfileEntity] {
        profiles().filter { identifiers.contains($0.id) }.map(FocusProfileEntity.init)
    }

    func entities(matching string: String) async throws -> [FocusProfileEntity] {
        profiles().filter { $0.name.localizedCaseInsensitiveContains(string) }.map(FocusProfileEntity.init)
    }

    func suggestedEntities() async throws -> [FocusProfileEntity] {
        profiles().map(FocusProfileEntity.init)
    }
}

// MARK: - Focus Filter (System Settings › Focus › <Focus> › Focus Filters › VideoWallpaper)

struct VideoWallpaperFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Set Video Wallpaper"
    static var description: IntentDescription? = IntentDescription(
        "Shows a VideoWallpaper Focus profile (set up in the app's Focus Modes screen) or a specific wallpaper while this Focus is on."
    )

    @Parameter(title: "Focus Profile")
    var profile: FocusProfileEntity?

    @Parameter(title: "Or Wallpaper")
    var wallpaper: WallpaperEntity?

    var displayRepresentation: DisplayRepresentation {
        if let profile {
            return DisplayRepresentation(title: "\(profile.name)", subtitle: "VideoWallpaper Focus profile")
        }
        if let wallpaper {
            return DisplayRepresentation(title: "\(wallpaper.name)", subtitle: "Video wallpaper")
        }
        return DisplayRepresentation(title: "No change")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.start()
        AppModel.shared.applyFocusFilter(profileID: profile?.id, wallpaperID: wallpaper?.id)
        return .result()
    }
}

// MARK: - Shortcuts actions
// Use these with Shortcuts › Automation › "When <Focus> turns on/off" (macOS 26+), or in any shortcut.

struct ActivateFocusWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn On Focus Wallpaper"
    static var description: IntentDescription? = IntentDescription(
        "Switches to the wallpaper assigned to a Focus profile in VideoWallpaper. Pair with a “When Focus turns on” automation."
    )

    @Parameter(title: "Focus Profile")
    var profile: FocusProfileEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Turn on \(\.$profile) wallpaper")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.start()
        AppModel.shared.activateFocus(profile.id)
        return .result()
    }
}

struct DeactivateFocusWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn Off Focus Wallpaper"
    static var description: IntentDescription? = IntentDescription(
        "Returns to your regular wallpaper. Leave the profile empty to turn off every Focus wallpaper."
    )

    @Parameter(title: "Focus Profile")
    var profile: FocusProfileEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Turn off \(\.$profile) wallpaper")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.start()
        AppModel.shared.deactivateFocus(profile?.id)
        return .result()
    }
}

struct SetVideoWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Video Wallpaper"
    static var description: IntentDescription? = IntentDescription("Sets the video wallpaper on all displays.")

    @Parameter(title: "Wallpaper")
    var wallpaper: WallpaperEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Set video wallpaper to \(\.$wallpaper)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.start()
        AppModel.shared.setWallpaper(wallpaper.id)
        return .result()
    }
}

struct NextVideoWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Video Wallpaper"
    static var description: IntentDescription? = IntentDescription("Switches to the next wallpaper in your library.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.start()
        AppModel.shared.next()
        return .result()
    }
}

struct PauseVideoWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Video Wallpaper"

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.start()
        AppModel.shared.setPaused(true)
        return .result()
    }
}

struct ResumeVideoWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Video Wallpaper"

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.start()
        AppModel.shared.setPaused(false)
        return .result()
    }
}
