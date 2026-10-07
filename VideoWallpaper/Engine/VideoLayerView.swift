import AppKit
import AVFoundation

/// Plays a muted, seamlessly looping video and crossfades between videos.
@MainActor
final class VideoLayerView: NSView {
    private final class Slot {
        let id = UUID()
        let player: AVQueuePlayer
        let looper: AVPlayerLooper
        let layer: AVPlayerLayer
        var readyObservation: NSKeyValueObservation?
        var revealed = false

        init(url: URL, gravity: AVLayerVideoGravity) {
            let item = AVPlayerItem(asset: AVURLAsset(url: url))
            player = AVQueuePlayer()
            player.isMuted = true
            player.volume = 0
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.allowsExternalPlayback = false
            looper = AVPlayerLooper(player: player, templateItem: item)
            layer = AVPlayerLayer(player: player)
            layer.videoGravity = gravity
            layer.backgroundColor = NSColor.black.cgColor
        }

        func teardown() {
            readyObservation?.invalidate()
            readyObservation = nil
            looper.disableLooping()
            player.pause()
            player.removeAllItems()
            layer.player = nil
            layer.removeFromSuperlayer()
        }
    }

    /// Oldest first; the last slot is the one being shown (or faded in).
    private var slots: [Slot] = []
    private var wantsPlayback = true

    var crossfadeDuration: TimeInterval = 1.2

    var videoGravity: AVLayerVideoGravity = .resizeAspectFill {
        didSet {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            slots.forEach { $0.layer.videoGravity = videoGravity }
            CATransaction.commit()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        slots.forEach { $0.layer.frame = bounds }
        CATransaction.commit()
    }

    var hasContent: Bool { !slots.isEmpty }

    struct PlaybackStatus {
        let isPlaying: Bool
        let isReadyForDisplay: Bool
        let currentTime: Double
        let error: String?
    }

    var playbackStatus: PlaybackStatus? {
        guard let slot = slots.last else { return nil }
        return PlaybackStatus(
            isPlaying: slot.player.timeControlStatus == .playing,
            isReadyForDisplay: slot.layer.isReadyForDisplay,
            currentTime: slot.player.currentTime().seconds,
            error: (slot.player.currentItem?.error ?? slot.player.error)?.localizedDescription
        )
    }

    func play(url: URL, animated: Bool) {
        let slot = Slot(url: url, gravity: videoGravity)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        slot.layer.frame = bounds
        slot.layer.opacity = 0
        layer?.addSublayer(slot.layer)
        CATransaction.commit()
        slots.append(slot)

        if wantsPlayback {
            slot.player.play()
        }

        let slotID = slot.id
        let duration = animated ? crossfadeDuration : 0
        if slot.layer.isReadyForDisplay {
            reveal(slotID, duration: duration)
            return
        }
        slot.readyObservation = slot.layer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor [weak self] in
                self?.reveal(slotID, duration: duration)
            }
        }
        // Fallback in case the readiness notification never arrives (e.g. while the display sleeps).
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.reveal(slotID, duration: duration)
        }
    }

    func stop() {
        let all = slots
        slots.removeAll()
        all.forEach { $0.teardown() }
    }

    func pause() {
        wantsPlayback = false
        slots.forEach { $0.player.pause() }
    }

    func resume() {
        wantsPlayback = true
        slots.forEach { $0.player.play() }
    }

    /// Restarts playback after sleep or display reconfiguration, recreating the player if it failed.
    func recover(url: URL?) {
        guard let current = slots.last else { return }
        let failed = current.player.status == .failed || current.player.currentItem?.status == .failed
        if failed, let url {
            play(url: url, animated: false)
        } else if wantsPlayback {
            current.player.play()
        }
    }

    private func reveal(_ slotID: UUID, duration: TimeInterval) {
        guard let index = slots.firstIndex(where: { $0.id == slotID }) else { return }
        let slot = slots[index]
        guard !slot.revealed else { return }
        slot.revealed = true
        slot.readyObservation?.invalidate()
        slot.readyObservation = nil

        // Everything underneath this slot can go once it is fully opaque.
        let older = Array(slots[..<index])
        let olderIDs = Set(older.map(\.id))

        CATransaction.begin()
        if duration > 0 {
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor [weak self] in
                self?.retire(olderIDs)
            }
        }
        slot.layer.opacity = 1
        CATransaction.commit()
    }

    private func retire(_ ids: Set<UUID>) {
        let retiring = slots.filter { ids.contains($0.id) }
        slots.removeAll { ids.contains($0.id) }
        retiring.forEach { $0.teardown() }
    }
}
