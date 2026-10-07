import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Wrapper for passing non-Sendable values (CGImage, NSImage) out of background tasks.
struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
}

enum MediaError: LocalizedError {
    case notPlayable
    case noVideoTrack
    case imageWriteFailed

    var errorDescription: String? {
        switch self {
        case .notPlayable: return "This file can't be played by macOS. Use an MP4 or MOV (H.264, HEVC or ProRes)."
        case .noVideoTrack: return "This file doesn't contain a video track."
        case .imageWriteFailed: return "Couldn't write the image."
        }
    }
}

struct VideoInfo: Sendable {
    var width: Int
    var height: Int
    var duration: Double
    var fileSize: Int64?
}

enum VideoInspector {
    static let supportedExtensions: Set<String> = ["mp4", "mov", "m4v"]

    static func inspect(_ url: URL) async throws -> VideoInfo {
        let asset = AVURLAsset(url: url)
        let (playable, duration) = try await asset.load(.isPlayable, .duration)
        guard playable else { throw MediaError.notPlayable }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw MediaError.noVideoTrack
        }
        let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
        let rect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value
        return VideoInfo(
            width: Int(abs(rect.width).rounded()),
            height: Int(abs(rect.height).rounded()),
            duration: duration.seconds,
            fileSize: fileSize
        )
    }
}

enum Thumbnailer {
    static func makeThumbnail(for videoURL: URL, to destination: URL) async throws {
        let image = try await frame(of: videoURL, maxSize: CGSize(width: 640, height: 360), at: 1.0)
        try writeJPEG(image.value, to: destination, quality: 0.82)
    }

    static func frame(of videoURL: URL, maxSize: CGSize, at seconds: Double) async throws -> UncheckedSendable<CGImage> {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let duration = try await asset.load(.duration).seconds
        let time = duration.isFinite && duration > 0 ? min(seconds, duration * 0.25) : 0
        let (image, _) = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
        return UncheckedSendable(value: image)
    }

    static func writeJPEG(_ image: CGImage, to url: URL, quality: Double) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw MediaError.imageWriteFailed
        }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { throw MediaError.imageWriteFailed }
    }
}
