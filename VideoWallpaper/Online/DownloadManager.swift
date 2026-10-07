import Foundation

struct DownloadRequest: Sendable {
    let remoteID: String
    let title: String
    let provider: String
    let author: String?
    let pageURL: URL?
    let thumbnailURL: URL?
    let fileURL: URL
    let setWhenFinished: Bool
}

struct DownloadItem: Identifiable {
    enum Phase: Equatable {
        case downloading
        case processing
        case finished
        case failed(String)
    }

    let id: UUID
    let request: DownloadRequest
    var receivedBytes: Int64 = 0
    var expectedBytes: Int64 = 0
    var phase: Phase = .downloading

    var isActive: Bool { phase == .downloading || phase == .processing }

    /// 0...1, or nil while the size is unknown.
    var fraction: Double? {
        guard expectedBytes > 0 else { return nil }
        return min(1, Double(receivedBytes) / Double(expectedBytes))
    }

    var progressText: String {
        switch phase {
        case .downloading:
            let received = ByteCountFormatter.string(fromByteCount: receivedBytes, countStyle: .file)
            guard expectedBytes > 0 else { return received }
            return "\(received) of \(ByteCountFormatter.string(fromByteCount: expectedBytes, countStyle: .file))"
        case .processing: return "Adding to library…"
        case .finished: return "Added to library"
        case .failed(let message): return message
        }
    }
}

@MainActor
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var items: [DownloadItem] = []
    private var tasks: [UUID: URLSessionDownloadTask] = [:]

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.httpAdditionalHeaders = ["User-Agent": "VideoWallpaper/1.0 (macOS)"]
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
    }

    var activeCount: Int { items.filter(\.isActive).count }

    func item(forRemoteID remoteID: String) -> DownloadItem? {
        items.first { $0.request.remoteID == remoteID }
    }

    func start(_ request: DownloadRequest) {
        if let existing = item(forRemoteID: request.remoteID), existing.isActive { return }
        items.removeAll { $0.request.remoteID == request.remoteID }

        let id = UUID()
        let task = session.downloadTask(with: request.fileURL)
        task.taskDescription = id.uuidString
        tasks[id] = task
        items.insert(DownloadItem(id: id, request: request), at: 0)
        task.resume()
    }

    func cancel(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        items.removeAll { $0.id == id }
    }

    func dismiss(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }), !item.isActive else { return }
        items.removeAll { $0.id == id }
    }

    func clearCompleted() {
        items.removeAll { !$0.isActive }
    }

    private func updateProgress(id: UUID, received: Int64, expected: Int64) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].phase == .downloading else { return }
        items[index].receivedBytes = received
        items[index].expectedBytes = max(0, expected)
    }

    private func setPhase(_ id: UUID, _ phase: DownloadItem.Phase) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].phase = phase
    }

    private func finishDownload(id: UUID, stagedFile: URL?, error: String?) {
        tasks[id] = nil
        guard let item = items.first(where: { $0.id == id }) else {
            if let stagedFile { try? FileManager.default.removeItem(at: stagedFile) }
            return
        }
        if let error {
            setPhase(id, .failed(error))
            return
        }
        guard let stagedFile else { return }
        setPhase(id, .processing)
        let request = item.request
        Task {
            do {
                let wallpaper = try await LibraryStore.shared.addVideo(
                    from: stagedFile,
                    move: true,
                    name: request.title,
                    origin: .downloaded,
                    provider: request.provider,
                    author: request.author,
                    pageURL: request.pageURL,
                    remoteID: request.remoteID
                )
                setPhase(id, .finished)
                AppModel.shared.wallpaperAdded(wallpaper, makeCurrent: request.setWhenFinished)
            } catch {
                try? FileManager.default.removeItem(at: stagedFile)
                setPhase(id, .failed(error.localizedDescription))
            }
        }
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = downloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        Task { @MainActor in
            self.updateProgress(id: id, received: totalBytesWritten, expected: totalBytesExpectedToWrite)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<300).contains(status) else {
            Task { @MainActor in
                self.finishDownload(id: id, stagedFile: nil, error: "Download failed (HTTP \(status)).")
            }
            return
        }
        // The temporary file is deleted when this method returns, so move it synchronously.
        let staged = AppPaths.staging.appendingPathComponent("\(id.uuidString).\(Self.fileExtension(for: downloadTask))")
        do {
            try? FileManager.default.removeItem(at: staged)
            try FileManager.default.moveItem(at: location, to: staged)
            Task { @MainActor in
                self.finishDownload(id: id, stagedFile: staged, error: nil)
            }
        } catch {
            let message = error.localizedDescription
            Task { @MainActor in
                self.finishDownload(id: id, stagedFile: nil, error: message)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = task.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        let message = error.localizedDescription
        Task { @MainActor in
            self.finishDownload(id: id, stagedFile: nil, error: message)
        }
    }

    nonisolated private static func fileExtension(for task: URLSessionDownloadTask) -> String {
        let supported = VideoInspector.supportedExtensions
        if let suggested = task.response?.suggestedFilename {
            let ext = (suggested as NSString).pathExtension.lowercased()
            if supported.contains(ext) { return ext }
        }
        for url in [task.response?.url, task.currentRequest?.url, task.originalRequest?.url].compactMap({ $0 }) {
            let ext = url.pathExtension.lowercased()
            if supported.contains(ext) { return ext }
        }
        if task.response?.mimeType?.contains("quicktime") == true { return "mov" }
        return "mp4"
    }
}
