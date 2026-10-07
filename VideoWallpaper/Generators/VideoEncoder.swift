import AVFoundation
import CoreGraphics
import CoreVideo

/// Draws one frame of a generated wallpaper. Frame `totalFrames` must equal frame 0 so the video loops seamlessly.
protocol FrameRenderer: AnyObject {
    func render(frame: Int, into context: CGContext)
}

enum GeneratorError: LocalizedError {
    case unsupportedFormat
    case writerFailed(String?)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "This Mac can't encode video at that resolution. Try a lower resolution."
        case .writerFailed(let detail):
            guard let detail else { return "Video encoding failed." }
            return "Video encoding failed: \(detail)"
        }
    }
}

enum VideoEncoder {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    static let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

    /// Renders `request` to a HEVC (or H.264) QuickTime movie at `url`.
    static func render(request: GeneratorRequest, to url: URL, cancel: CancellationFlag, progress: @escaping @Sendable (Double) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let session = try EncodingSession(request: request, url: url, cancel: cancel, progress: progress, continuation: continuation)
                session.start()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Renders a single frame, used for live previews in the Create screen.
    static func previewImage(request: GeneratorRequest, frame: Int = 0) -> CGImage? {
        let renderer = request.makeRenderer()
        guard let context = CGContext(
            data: nil,
            width: request.width,
            height: request.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        renderer.render(frame: frame, into: context)
        return context.makeImage()
    }

    static func outputSettings(codec: AVVideoCodecType, width: Int, height: Int, fps: Int) -> [String: Any] {
        let bitrate = max(6_000_000, Int(Double(width * height * fps) * 0.08))
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoMaxKeyFrameIntervalKey: fps * 2,
        ]
        if codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        return [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: compression,
        ]
    }
}

/// Pulls frames from a renderer into AVAssetWriter on a private queue.
private final class EncodingSession: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let renderer: FrameRenderer
    private let queue = DispatchQueue(label: "com.natentate.VideoWallpaper.encoder", qos: .userInitiated)
    private let totalFrames: Int
    private let fps: Int32
    private let cancel: CancellationFlag
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var frame = 0
    private var finishing = false
    private var lastReportedPercent = -1

    init(request: GeneratorRequest, url: URL, cancel: CancellationFlag, progress: @escaping @Sendable (Double) -> Void, continuation: CheckedContinuation<Void, Error>) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        var settings = VideoEncoder.outputSettings(codec: .hevc, width: request.width, height: request.height, fps: request.fps)
        if !writer.canApply(outputSettings: settings, forMediaType: .video) {
            settings = VideoEncoder.outputSettings(codec: .h264, width: request.width, height: request.height, fps: request.fps)
        }
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
            throw GeneratorError.unsupportedFormat
        }

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: request.width,
                kCVPixelBufferHeightKey as String: request.height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            ]
        )
        guard writer.canAdd(input) else { throw GeneratorError.unsupportedFormat }
        writer.add(input)

        self.writer = writer
        self.input = input
        self.adaptor = adaptor
        renderer = request.makeRenderer()
        totalFrames = request.totalFrames
        fps = Int32(request.fps)
        self.cancel = cancel
        self.progress = progress
        self.continuation = continuation
    }

    func start() {
        guard writer.startWriting() else {
            complete(.failure(GeneratorError.writerFailed(writer.error?.localizedDescription)))
            return
        }
        writer.startSession(atSourceTime: .zero)
        input.requestMediaDataWhenReady(on: queue) { [self] in
            pump()
        }
    }

    private func pump() {
        guard !finishing else { return }
        while input.isReadyForMoreMediaData {
            if cancel.isCancelled {
                finishing = true
                input.markAsFinished()
                writer.cancelWriting()
                complete(.failure(CancellationError()))
                return
            }
            if frame >= totalFrames {
                finishing = true
                input.markAsFinished()
                writer.finishWriting { [self] in
                    if writer.status == .completed {
                        complete(.success(()))
                    } else {
                        complete(.failure(GeneratorError.writerFailed(writer.error?.localizedDescription)))
                    }
                }
                return
            }
            guard appendFrame() else {
                finishing = true
                input.markAsFinished()
                writer.cancelWriting()
                complete(.failure(GeneratorError.writerFailed(writer.error?.localizedDescription)))
                return
            }
            frame += 1
            let percent = frame * 100 / totalFrames
            if percent != lastReportedPercent {
                lastReportedPercent = percent
                progress(Double(frame) / Double(totalFrames))
            }
        }
    }

    private func appendFrame() -> Bool {
        guard let pool = adaptor.pixelBufferPool else { return false }
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        guard let buffer = pixelBuffer else { return false }

        CVPixelBufferLockBaseAddress(buffer, [])
        if let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: VideoEncoder.colorSpace,
            bitmapInfo: VideoEncoder.bitmapInfo
        ) {
            renderer.render(frame: frame, into: context)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        return adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
    }

    private func complete(_ result: Result<Void, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
