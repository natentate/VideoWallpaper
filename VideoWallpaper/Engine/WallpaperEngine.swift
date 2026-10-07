import AppKit
import AVFoundation

/// Drives one desktop window per connected display.
@MainActor
final class WallpaperEngine {
    private var controllers: [String: ScreenController] = [:]

    var videoGravity: AVLayerVideoGravity = .resizeAspectFill {
        didSet { controllers.values.forEach { $0.videoView.videoGravity = videoGravity } }
    }

    var crossfade = true

    var pauseWhenCovered = true {
        didSet { updatePlayback() }
    }

    /// Global switch (manual pause, lock screen, battery rules, ...).
    var isPlaybackAllowed = true {
        didSet { updatePlayback() }
    }

    /// - Parameter assignments: display id → video file. Displays without an entry show the system wallpaper.
    func sync(assignments: [String: URL]) {
        var seen = Set<String>()
        for screen in NSScreen.screens {
            let id = screen.stableID
            seen.insert(id)
            let controller: ScreenController
            if let existing = controllers[id] {
                controller = existing
                controller.update(screen: screen)
            } else {
                controller = ScreenController(screen: screen)
                controller.videoView.videoGravity = videoGravity
                controller.onVisibilityChange = { [weak self] in self?.updatePlayback() }
                controllers[id] = controller
            }
            controller.show(url: assignments[id], animated: crossfade)
        }
        for (id, controller) in controllers where !seen.contains(id) {
            controller.teardown()
            controllers[id] = nil
        }
        updatePlayback()
    }

    func recover() {
        controllers.values.forEach { $0.recover() }
        updatePlayback()
    }

    func teardown() {
        controllers.values.forEach { $0.teardown() }
        controllers.removeAll()
    }

    private func updatePlayback() {
        for controller in controllers.values {
            let visible = !pauseWhenCovered || controller.isVisible
            controller.setPlaying(isPlaybackAllowed && visible)
        }
    }
}

@MainActor
final class ScreenController {
    let window: DesktopWindow
    let videoView: VideoLayerView
    private(set) var url: URL?
    private(set) var isVisible = true
    var onVisibilityChange: (() -> Void)?
    private var occlusionObserver: NSObjectProtocol?

    init(screen: NSScreen) {
        window = DesktopWindow(screen: screen)
        videoView = VideoLayerView(frame: NSRect(origin: .zero, size: screen.frame.size))
        videoView.autoresizingMask = [.width, .height]
        window.contentView = videoView

        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.occlusionChanged()
            }
        }
    }

    func update(screen: NSScreen) {
        if window.frame != screen.frame {
            window.setFrame(screen.frame, display: true)
        }
    }

    func show(url: URL?, animated: Bool) {
        guard url != self.url else { return }
        self.url = url
        if let url {
            let wasOnScreen = window.isVisible && videoView.hasContent
            window.orderFrontRegardless()
            videoView.play(url: url, animated: animated && wasOnScreen)
        } else {
            videoView.stop()
            window.orderOut(nil)
        }
    }

    func setPlaying(_ playing: Bool) {
        if playing {
            videoView.resume()
        } else {
            videoView.pause()
        }
    }

    func recover() {
        videoView.recover(url: url)
    }

    func teardown() {
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
        occlusionObserver = nil
        videoView.stop()
        window.orderOut(nil)
        url = nil
    }

    private func occlusionChanged() {
        let visible = window.occlusionState.contains(.visible)
        guard visible != isVisible else { return }
        isVisible = visible
        onVisibilityChange?()
    }
}
