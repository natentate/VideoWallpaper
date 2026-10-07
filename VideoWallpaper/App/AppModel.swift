import AppKit
import Combine
import Foundation

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let isError: Bool
}

/// Central coordinator: decides which wallpaper plays on which display (default, per-display,
/// Focus overrides), applies playback rules and handles commands from the UI, menu bar,
/// Shortcuts, Focus Filters and the `videowallpaper://` URL scheme.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let library = LibraryStore.shared
    let preferences = Preferences.shared
    let discover = DiscoverModel()
    private let system = SystemActivityMonitor()
    private let engine = WallpaperEngine()

    @Published var selectedSection: SidebarItem? = .library
    @Published private(set) var state = PersistedState()
    @Published private(set) var displays: [DisplayInfo] = []
    /// Display id → wallpaper currently on screen.
    @Published private(set) var nowPlaying: [String: UUID] = [:]
    @Published private(set) var statusText = "Starting…"
    @Published private(set) var isPlaybackBlocked = false
    @Published var toast: Toast?

    private var started = false
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var rotationTimer: Timer?
    private var scheduledRotation: RotationInterval?

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        AppPaths.prepare()
        library.load()
        state = PersistedState.load()
        if !state.hasLaunchedBefore {
            state.hasLaunchedBefore = true
            state.defaultWallpaperID = library.wallpapers.first?.id
        }
        if library.wallpaper(id: state.defaultWallpaperID) == nil {
            state.defaultWallpaperID = library.wallpapers.first?.id
        }
        state.save()

        system.onChange = { [unowned self] in self.updatePlayback() }
        system.onWake = { [unowned self] in
            self.refreshDisplays()
            self.engine.recover()
        }
        system.start()

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in AppModel.shared.screensChanged() }
        })

        preferences.objectWillChange
            .sink { _ in
                // objectWillChange fires before the new value is stored; read it on the next turn.
                Task { @MainActor in AppModel.shared.preferencesChanged() }
            }
            .store(in: &cancellables)

        configureEngine()
        refreshDisplays()
        apply()
        scheduleRotation()
        discover.bootstrap()
    }

    var engineStatus: [WallpaperEngine.ScreenStatus] { engine.status }

    func shutdown() {
        engine.teardown()
        state.save()
    }

    private func screensChanged() {
        refreshDisplays()
        apply()
    }

    private func refreshDisplays() {
        displays = NSScreen.screens.map { DisplayInfo(screen: $0) }
    }

    private func preferencesChanged() {
        configureEngine()
        updatePlayback()
        if scheduledRotation != preferences.rotationInterval {
            scheduleRotation()
        }
        if preferences.syncDesktopPicture {
            DesktopPictureSync.sync(nowPlaying: nowPlaying, library: library)
        } else {
            DesktopPictureSync.reset()
        }
    }

    private func configureEngine() {
        engine.videoGravity = preferences.scaling.gravity
        engine.crossfade = preferences.crossfade
        engine.pauseWhenCovered = preferences.pauseWhenCovered
    }

    // MARK: - Resolution

    /// The wallpaper that should be on `displayID` right now.
    func wallpaperID(for displayID: String) -> UUID? {
        focusWallpaperID(for: displayID) ?? baseWallpaperID(for: displayID)
    }

    /// The wallpaper ignoring Focus overrides.
    func baseWallpaperID(for displayID: String) -> UUID? {
        if !state.sameOnAllDisplays, let id = state.perDisplayWallpaper[displayID], library.wallpaper(id: id) != nil {
            return id
        }
        return state.defaultWallpaperID
    }

    private func focusWallpaperID(for displayID: String) -> UUID? {
        for activation in state.activations.reversed() {
            if let profileID = activation.profileID {
                guard let profile = focusProfile(id: profileID) else { continue }
                if let id = profile.perDisplay[displayID] ?? profile.wallpaperID, library.wallpaper(id: id) != nil {
                    return id
                }
            } else if let id = activation.wallpaperID, library.wallpaper(id: id) != nil {
                return id
            }
        }
        return nil
    }

    /// The most recently activated Focus profile, if any.
    var activeFocusProfile: FocusProfile? {
        for activation in state.activations.reversed() {
            if let id = activation.profileID, let profile = focusProfile(id: id) {
                return profile
            }
        }
        return nil
    }

    var activeFocusDescription: String? {
        guard let activation = state.activations.last else { return nil }
        if let id = activation.profileID, let profile = focusProfile(id: id) {
            return profile.name
        }
        if let id = activation.wallpaperID, let wallpaper = library.wallpaper(id: id) {
            return "Focus Filter · \(wallpaper.name)"
        }
        return nil
    }

    private var focusPausesPlayback: Bool {
        state.activations.contains { activation in
            activation.profileID.flatMap { focusProfile(id: $0) }?.pausesPlayback ?? false
        }
    }

    // MARK: - Applying

    func apply() {
        var assignments: [String: URL] = [:]
        var playing: [String: UUID] = [:]
        for display in displays {
            guard let id = wallpaperID(for: display.id), let wallpaper = library.wallpaper(id: id) else { continue }
            guard FileManager.default.fileExists(atPath: wallpaper.fileURL.path) else { continue }
            assignments[display.id] = wallpaper.fileURL
            playing[display.id] = id
        }
        if playing != nowPlaying {
            nowPlaying = playing
        }
        engine.sync(assignments: assignments)
        updatePlayback()
        if preferences.syncDesktopPicture {
            DesktopPictureSync.sync(nowPlaying: playing, library: library)
        }
    }

    private func updatePlayback() {
        let reason = playbackBlockReason
        engine.isPlaybackAllowed = reason == nil
        isPlaybackBlocked = reason != nil
        if nowPlaying.isEmpty {
            statusText = library.wallpapers.isEmpty ? "Add a wallpaper to get started" : "No wallpaper selected"
        } else {
            statusText = reason ?? "Playing"
        }
    }

    private var playbackBlockReason: String? {
        if state.isPaused { return "Paused" }
        if focusPausesPlayback { return "Paused by Focus" }
        if system.isScreenLocked { return "Paused — screen locked" }
        if system.isScreenSaverRunning { return "Paused — screen saver" }
        if system.areScreensAsleep || system.isSystemAsleep { return "Paused — display asleep" }
        if system.isSessionInactive { return "Paused — switched user" }
        if preferences.pauseOnBattery && system.isOnBattery { return "Paused — on battery" }
        if preferences.pauseInLowPowerMode && system.isLowPowerMode { return "Paused — Low Power Mode" }
        return nil
    }

    private func commit() {
        state.save()
        apply()
    }

    // MARK: - Wallpaper commands

    /// Sets a wallpaper on every display, or on one display when `displayID` is given.
    /// A manual choice replaces any active Focus wallpaper so the result is visible immediately.
    func setWallpaper(_ id: UUID, on displayID: String? = nil) {
        if let displayID, displays.count > 1 {
            if state.sameOnAllDisplays {
                for display in displays {
                    state.perDisplayWallpaper[display.id] = state.defaultWallpaperID
                }
                state.sameOnAllDisplays = false
            }
            state.perDisplayWallpaper[displayID] = id
        } else {
            state.defaultWallpaperID = id
            state.perDisplayWallpaper = [:]
            state.sameOnAllDisplays = true
        }
        state.activations.removeAll()
        commit()
    }

    func setSameOnAllDisplays(_ same: Bool) {
        guard same != state.sameOnAllDisplays else { return }
        if same {
            state.perDisplayWallpaper = [:]
        } else {
            for display in displays {
                state.perDisplayWallpaper[display.id] = state.defaultWallpaperID
            }
        }
        state.sameOnAllDisplays = same
        commit()
    }

    func clearWallpaper() {
        state.defaultWallpaperID = nil
        state.perDisplayWallpaper = [:]
        state.activations.removeAll()
        commit()
    }

    private func rotationPool() -> [Wallpaper] {
        let favorites = library.favorites
        if preferences.rotationSource == .favorites, favorites.count > 1 {
            return favorites
        }
        return library.wallpapers
    }

    /// Advances to the next wallpaper in the rotation pool.
    func next() {
        let pool = rotationPool()
        guard !pool.isEmpty else { return }
        func successor(of id: UUID?) -> UUID {
            guard let id, let index = pool.firstIndex(where: { $0.id == id }) else { return pool[0].id }
            return pool[(index + 1) % pool.count].id
        }
        if state.sameOnAllDisplays || displays.count <= 1 {
            state.defaultWallpaperID = successor(of: state.defaultWallpaperID)
        } else {
            for display in displays {
                state.perDisplayWallpaper[display.id] = successor(of: baseWallpaperID(for: display.id))
            }
        }
        state.activations.removeAll()
        commit()
    }

    func setPaused(_ paused: Bool) {
        guard state.isPaused != paused else { return }
        state.isPaused = paused
        commit()
    }

    func togglePause() {
        setPaused(!state.isPaused)
    }

    func wallpaperAdded(_ wallpaper: Wallpaper, makeCurrent: Bool) {
        if makeCurrent || state.defaultWallpaperID == nil {
            setWallpaper(wallpaper.id)
            showToast("Now playing “\(wallpaper.name)”")
        } else {
            showToast("Added “\(wallpaper.name)” to your library")
        }
    }

    func deleteWallpapers(_ ids: Set<UUID>) {
        library.remove(ids: ids)
        if let current = state.defaultWallpaperID, ids.contains(current) {
            state.defaultWallpaperID = library.wallpapers.first?.id
        }
        state.perDisplayWallpaper = state.perDisplayWallpaper.filter { !ids.contains($0.value) }
        for index in state.focusProfiles.indices {
            if let id = state.focusProfiles[index].wallpaperID, ids.contains(id) {
                state.focusProfiles[index].wallpaperID = nil
            }
            state.focusProfiles[index].perDisplay = state.focusProfiles[index].perDisplay.filter { !ids.contains($0.value) }
        }
        state.activations.removeAll { activation in
            activation.wallpaperID.map { ids.contains($0) } ?? false
        }
        commit()
    }

    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            let result = await library.importFiles(urls)
            if let first = result.imported.first, state.defaultWallpaperID == nil {
                setWallpaper(first.id)
            }
            if !result.failures.isEmpty {
                showToast(result.failures.joined(separator: "\n"), isError: true)
            } else if result.imported.count == 1, let wallpaper = result.imported.first {
                showToast("Imported “\(wallpaper.name)”")
            } else if result.imported.count > 1 {
                showToast("Imported \(result.imported.count) videos")
            }
        }
    }

    // MARK: - Rotation

    private func scheduleRotation() {
        rotationTimer?.invalidate()
        rotationTimer = nil
        scheduledRotation = preferences.rotationInterval
        guard let interval = preferences.rotationInterval.seconds else { return }
        rotationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in AppModel.shared.rotate() }
        }
    }

    private func rotate() {
        // Don't fight a Focus wallpaper or a manual pause.
        guard state.activations.isEmpty, !state.isPaused else { return }
        next()
    }

    // MARK: - Focus

    func focusProfile(id: UUID) -> FocusProfile? {
        state.focusProfiles.first { $0.id == id }
    }

    func focusProfile(named name: String) -> FocusProfile? {
        func normalized(_ value: String) -> String {
            value.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let needle = normalized(name)
        guard !needle.isEmpty else { return nil }
        return state.focusProfiles.first { normalized($0.name) == needle }
    }

    func isFocusActive(_ profileID: UUID) -> Bool {
        state.activations.contains { $0.profileID == profileID }
    }

    func activateFocus(_ profileID: UUID, source: FocusActivation.Source = .shortcut) {
        guard focusProfile(id: profileID) != nil else { return }
        state.activations.removeAll { $0.profileID == profileID && $0.source == source }
        state.activations.append(FocusActivation(profileID: profileID, wallpaperID: nil, source: source, date: Date()))
        commit()
    }

    /// Ends a Focus wallpaper. With no profile, ends all of them.
    func deactivateFocus(_ profileID: UUID?) {
        if let profileID {
            state.activations.removeAll { $0.profileID == profileID }
        } else {
            state.activations.removeAll()
        }
        commit()
    }

    /// Called by the Focus Filter when a Focus turns on (with values) or off (with defaults, i.e. nil).
    func applyFocusFilter(profileID: UUID?, wallpaperID: UUID?) {
        state.activations.removeAll { $0.source == .focusFilter }
        if let profileID, focusProfile(id: profileID) != nil {
            state.activations.append(FocusActivation(profileID: profileID, wallpaperID: nil, source: .focusFilter, date: Date()))
        } else if let wallpaperID {
            state.activations.append(FocusActivation(profileID: nil, wallpaperID: wallpaperID, source: .focusFilter, date: Date()))
        }
        commit()
    }

    @discardableResult
    func addFocusProfile(name: String, symbol: String) -> UUID {
        let profile = FocusProfile(name: name, symbol: symbol)
        state.focusProfiles.append(profile)
        commit()
        return profile.id
    }

    func updateFocusProfile(_ id: UUID, _ change: (inout FocusProfile) -> Void) {
        guard let index = state.focusProfiles.firstIndex(where: { $0.id == id }) else { return }
        change(&state.focusProfiles[index])
        commit()
    }

    func removeFocusProfile(_ id: UUID) {
        state.focusProfiles.removeAll { $0.id == id }
        state.activations.removeAll { $0.profileID == id }
        commit()
    }

    // MARK: - URL scheme

    /// videowallpaper://focus/on?name=Work · focus/off?name=Work · focus/off
    /// videowallpaper://set?name=Rain · next · pause · resume · toggle · open · discover?q=…
    func handle(url: URL) {
        start()
        guard url.scheme?.lowercased() == "videowallpaper" else { return }
        let host = (url.host ?? "").lowercased()
        let path = url.pathComponents.filter { $0 != "/" }.map { $0.lowercased() }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func parameter(_ name: String) -> String? {
            queryItems.first { $0.name.lowercased() == name }?.value
        }

        switch host {
        case "focus":
            let action = path.first ?? parameter("state") ?? "on"
            let profile = parameter("id").flatMap(UUID.init(uuidString:)).flatMap(focusProfile(id:))
                ?? parameter("name").flatMap(focusProfile(named:))
            if ["off", "end", "stop", "deactivate"].contains(action) {
                if profile != nil || parameter("name") == nil {
                    deactivateFocus(profile?.id)
                }
            } else if let profile {
                activateFocus(profile.id)
            } else {
                showToast("No Focus wallpaper named “\(parameter("name") ?? "")”. Add it under Focus Modes.", isError: true)
            }
        case "set", "wallpaper":
            let match = parameter("id").flatMap(UUID.init(uuidString:)).flatMap { library.wallpaper(id: $0) }
                ?? parameter("name").flatMap { library.wallpaper(named: $0) }
            guard let wallpaper = match else {
                showToast("No wallpaper named “\(parameter("name") ?? "")”.", isError: true)
                return
            }
            let display = parameter("display").flatMap { name in
                displays.first { $0.id == name || $0.name.localizedCaseInsensitiveContains(name) }
            }
            setWallpaper(wallpaper.id, on: display?.id)
        case "next", "shuffle":
            next()
        case "pause":
            setPaused(true)
        case "resume", "play":
            setPaused(false)
        case "toggle":
            togglePause()
        case "discover":
            MainWindowController.shared.show(section: .discover)
            if let query = parameter("q"), !query.isEmpty {
                discover.query = query
                discover.search()
            }
        default:
            MainWindowController.shared.show()
        }
    }

    // MARK: - Toasts

    func showToast(_ message: String, isError: Bool = false) {
        let toast = Toast(message: message, isError: isError)
        self.toast = toast
        Task {
            try? await Task.sleep(for: .seconds(isError ? 6 : 3.5))
            if self.toast?.id == toast.id {
                self.toast = nil
            }
        }
    }
}
