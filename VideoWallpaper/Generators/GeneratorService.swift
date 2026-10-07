import AppKit
import Foundation

@MainActor
final class GeneratorService: ObservableObject {
    static let shared = GeneratorService()

    struct Job: Identifiable {
        enum Phase: Equatable {
            case rendering
            case saving
            case finished(UUID)
            case failed(String)
            case cancelled
        }

        let id = UUID()
        let request: GeneratorRequest
        var progress: Double = 0
        var phase: Phase = .rendering
        let startedAt = Date()

        var isRunning: Bool { phase == .rendering || phase == .saving }
    }

    @Published private(set) var job: Job?
    private var cancelFlag: CancellationFlag?

    private init() {}

    var isBusy: Bool { job?.isRunning ?? false }

    func generate(_ request: GeneratorRequest, setWhenFinished: Bool) {
        guard !isBusy else { return }
        let flag = CancellationFlag()
        cancelFlag = flag
        let newJob = Job(request: request)
        job = newJob
        let jobID = newJob.id
        let output = AppPaths.staging.appendingPathComponent("\(UUID().uuidString).mov")

        Task {
            do {
                try await VideoEncoder.render(request: request, to: output, cancel: flag) { progress in
                    Task { @MainActor in
                        GeneratorService.shared.updateProgress(jobID, progress)
                    }
                }
                setPhase(jobID, .saving)
                let wallpaper = try await LibraryStore.shared.addVideo(
                    from: output,
                    move: true,
                    name: request.name,
                    origin: .generated,
                    provider: request.kind.title
                )
                setPhase(jobID, .finished(wallpaper.id))
                AppModel.shared.wallpaperAdded(wallpaper, makeCurrent: setWhenFinished)
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: output)
                setPhase(jobID, .cancelled)
            } catch {
                try? FileManager.default.removeItem(at: output)
                setPhase(jobID, .failed(error.localizedDescription))
            }
        }
    }

    func cancel() {
        cancelFlag?.cancel()
    }

    func dismiss() {
        guard !isBusy else { return }
        job = nil
    }

    private func updateProgress(_ id: UUID, _ progress: Double) {
        guard job?.id == id, job?.phase == .rendering else { return }
        job?.progress = progress
    }

    private func setPhase(_ id: UUID, _ phase: Job.Phase) {
        guard job?.id == id else { return }
        job?.phase = phase
        if phase == .saving { job?.progress = 1 }
    }

    /// Renders a quick low-resolution frame of the current settings for the Create screen.
    static func preview(_ request: GeneratorRequest) async -> NSImage? {
        let boxed = await Task.detached(priority: .userInitiated) { () -> UncheckedSendable<CGImage?> in
            UncheckedSendable(value: VideoEncoder.previewImage(request: request, frame: request.totalFrames / 3))
        }.value
        guard let image = boxed.value else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
