import CoreGraphics
import Foundation

enum GeneratorKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case matrix
    case starfield

    var id: String { rawValue }

    var title: String {
        switch self {
        case .matrix: return "Matrix Code Rain"
        case .starfield: return "Starfield"
        }
    }

    var subtitle: String {
        switch self {
        case .matrix: return "Cascading digital rain, rendered at your display's native resolution."
        case .starfield: return "Fly through deep space — gentle drift to full warp speed."
        }
    }

    var symbol: String {
        switch self {
        case .matrix: return "chevron.left.forwardslash.chevron.right"
        case .starfield: return "sparkles"
        }
    }
}

enum GeneratorResolution: String, CaseIterable, Identifiable, Sendable {
    case p1080
    case p1440
    case uhd
    case native

    var id: String { rawValue }

    var title: String {
        switch self {
        case .p1080: return "1080p"
        case .p1440: return "1440p"
        case .uhd: return "4K"
        case .native: return "Native"
        }
    }

    /// Even pixel dimensions (required by the encoders), capped at 8K.
    func size(native: CGSize) -> (width: Int, height: Int) {
        func even(_ value: Double) -> Int { max(2, Int(value / 2) * 2) }
        switch self {
        case .p1080: return (1920, 1080)
        case .p1440: return (2560, 1440)
        case .uhd: return (3840, 2160)
        case .native:
            let scale = min(1, 7680 / max(native.width, 1), 4320 / max(native.height, 1))
            return (even(native.width * scale), even(native.height * scale))
        }
    }
}

struct RGB: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    func mixed(with other: RGB, amount: Double) -> RGB {
        let t = min(max(amount, 0), 1)
        return RGB(red: red + (other.red - red) * t, green: green + (other.green - green) * t, blue: blue + (other.blue - blue) * t)
    }

    func scaled(_ factor: Double) -> RGB {
        RGB(red: red * factor, green: green * factor, blue: blue * factor)
    }

    func cgColor(alpha: Double = 1) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    static let white = RGB(red: 1, green: 1, blue: 1)
}

enum MatrixPalette: String, CaseIterable, Identifiable, Sendable {
    case classic, cyan, crimson, amber, violet, ice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic Green"
        case .cyan: return "Cyan"
        case .crimson: return "Crimson"
        case .amber: return "Amber"
        case .violet: return "Violet"
        case .ice: return "Ice White"
        }
    }

    var color: RGB {
        switch self {
        case .classic: return RGB(red: 0.0, green: 1.0, blue: 0.36)
        case .cyan: return RGB(red: 0.0, green: 0.85, blue: 1.0)
        case .crimson: return RGB(red: 1.0, green: 0.12, blue: 0.2)
        case .amber: return RGB(red: 1.0, green: 0.68, blue: 0.0)
        case .violet: return RGB(red: 0.7, green: 0.35, blue: 1.0)
        case .ice: return RGB(red: 0.78, green: 0.9, blue: 1.0)
        }
    }
}

enum RainSpeed: String, CaseIterable, Identifiable, Sendable {
    case calm, classic, frantic

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Fall speed range in glyph cells per second.
    var cellsPerSecond: ClosedRange<Double> {
        switch self {
        case .calm: return 5...11
        case .classic: return 9...20
        case .frantic: return 16...34
        }
    }
}

enum GlyphScale: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Number of glyph rows on screen.
    var rows: Double {
        switch self {
        case .small: return 64
        case .medium: return 48
        case .large: return 34
        }
    }
}

struct MatrixSettings: Hashable, Sendable {
    var palette: MatrixPalette = .classic
    var speed: RainSpeed = .classic
    var glyphScale: GlyphScale = .medium
    var density: Double = 0.7
    var depthLayer = true
    var mirroredGlyphs = true
}

enum StarfieldStyle: String, CaseIterable, Identifiable, Sendable {
    case drift, cruise, warp

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var loopSeconds: Int {
        switch self {
        case .drift: return 30
        case .cruise: return 20
        case .warp: return 12
        }
    }

    var cycles: ClosedRange<Int> {
        switch self {
        case .drift: return 1...1
        case .cruise: return 1...2
        case .warp: return 2...4
        }
    }

    /// Streak length expressed as depth travelled.
    var streak: Double {
        switch self {
        case .drift: return 0
        case .cruise: return 0.025
        case .warp: return 0.09
        }
    }
}

enum StarTint: String, CaseIterable, Identifiable, Sendable {
    case natural, blue, gold

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct StarfieldSettings: Hashable, Sendable {
    var style: StarfieldStyle = .cruise
    var density: Double = 0.6
    var nebula = true
    var tint: StarTint = .natural
}

struct GeneratorRequest: Sendable {
    var kind: GeneratorKind
    var width: Int
    var height: Int
    var fps: Int = 30
    var seconds: Int
    var seed: UInt64
    var matrix = MatrixSettings()
    var starfield = StarfieldSettings()
    var name: String

    var totalFrames: Int { fps * seconds }

    func makeRenderer() -> FrameRenderer {
        switch kind {
        case .matrix:
            return MatrixRainRenderer(width: width, height: height, fps: fps, totalFrames: totalFrames, settings: matrix, seed: seed)
        case .starfield:
            return StarfieldRenderer(width: width, height: height, totalFrames: totalFrames, settings: starfield, seed: seed)
        }
    }
}

/// Deterministic RNG so a given seed always renders the same video.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@inline(__always)
func hashMix(_ a: UInt64, _ b: UInt64, _ c: UInt64, _ d: UInt64 = 0) -> UInt64 {
    var x = a &* 0x9E37_79B9_7F4A_7C15
    x ^= b &* 0xC2B2_AE3D_27D4_EB4F
    x ^= c &* 0x1656_67B1_9E37_79F9
    x ^= d &* 0x27D4_EB2F_1656_67C5
    x ^= x >> 33
    x = x &* 0xFF51_AFD7_ED55_8CCD
    x ^= x >> 33
    x = x &* 0xC4CE_B9FE_1A85_EC53
    x ^= x >> 33
    return x
}

final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
