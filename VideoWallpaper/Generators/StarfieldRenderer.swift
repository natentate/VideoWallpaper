import CoreGraphics
import Foundation

/// Renders a 3D starfield flying towards the viewer over a static nebula backdrop.
/// Each star's depth cycles a whole number of times per loop, so the video loops seamlessly.
final class StarfieldRenderer: FrameRenderer {
    private struct Star {
        let x: Double
        let y: Double
        let cycles: Int
        let phase: Double
        let size: Double
        let color: RGB
    }

    private let width: Int
    private let height: Int
    private let totalFrames: Int
    private let stars: [Star]
    private let background: CGImage?
    private let focal: Double
    private let streak: Double
    private let pixelScale: Double
    private let nearPlane = 0.035

    init(width: Int, height: Int, totalFrames: Int, settings: StarfieldSettings, seed: UInt64) {
        self.width = width
        self.height = height
        self.totalFrames = max(1, totalFrames)
        streak = settings.style.streak
        pixelScale = Double(min(width, height)) / 1080
        focal = Double(min(width, height)) * 0.5

        var rng = SeededGenerator(seed: seed)
        let megapixels = Double(width * height) / 1_000_000
        let count = Int(megapixels * 260 * (0.35 + settings.density * 1.3))
        let aspect = Double(width) / Double(max(height, 1))
        let palette = StarfieldRenderer.palette(for: settings.tint)

        var stars: [Star] = []
        stars.reserveCapacity(count)
        for _ in 0..<count {
            stars.append(Star(
                x: Double.random(in: -1...1, using: &rng) * aspect,
                y: Double.random(in: -1...1, using: &rng),
                cycles: Int.random(in: settings.style.cycles, using: &rng),
                phase: Double.random(in: 0..<1, using: &rng),
                size: Double.random(in: 0.6...1.8, using: &rng),
                color: palette[Int.random(in: 0..<palette.count, using: &rng)]
            ))
        }
        self.stars = stars
        background = StarfieldRenderer.makeBackground(width: width, height: height, nebula: settings.nebula, rng: &rng)
    }

    func render(frame: Int, into context: CGContext) {
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        if let background {
            context.draw(background, in: bounds)
        } else {
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fill(bounds)
        }
        context.setLineCap(.round)

        let centerX = Double(width) / 2
        let centerY = Double(height) / 2
        let loopPosition = Double(frame % totalFrames) / Double(totalFrames)
        let margin = 40 * pixelScale

        for star in stars {
            var progress = Double(star.cycles) * loopPosition + star.phase
            progress -= progress.rounded(.down)
            let z = 1 - progress * (1 - nearPlane)
            let headX = centerX + star.x / z * focal
            let headY = centerY + star.y / z * focal
            guard headX > -margin, headX < Double(width) + margin, headY > -margin, headY < Double(height) + margin else { continue }

            let closeness = 1 - z
            let fadeIn = min(1, progress / 0.12)
            let alpha = fadeIn * min(1, 0.18 + closeness * 1.5)
            guard alpha > 0.01 else { continue }
            let lineWidth = max(0.8, star.size * pixelScale * (0.5 + 2.6 * closeness * closeness))

            context.setStrokeColor(star.color.cgColor(alpha: alpha))
            context.setFillColor(star.color.cgColor(alpha: alpha))

            let tailZ = min(1, z + streak * Double(star.cycles))
            let tailX = centerX + star.x / tailZ * focal
            let tailY = centerY + star.y / tailZ * focal
            if streak > 0, hypot(headX - tailX, headY - tailY) > lineWidth {
                context.setLineWidth(lineWidth)
                context.move(to: CGPoint(x: tailX, y: tailY))
                context.addLine(to: CGPoint(x: headX, y: headY))
                context.strokePath()
            } else {
                context.fillEllipse(in: CGRect(x: headX - lineWidth / 2, y: headY - lineWidth / 2, width: lineWidth, height: lineWidth))
            }
        }
    }

    private static func palette(for tint: StarTint) -> [RGB] {
        switch tint {
        case .natural:
            return [.white, .white, RGB(red: 0.8, green: 0.88, blue: 1), RGB(red: 1, green: 0.93, blue: 0.82), RGB(red: 0.7, green: 0.8, blue: 1)]
        case .blue:
            return [RGB(red: 0.6, green: 0.78, blue: 1), RGB(red: 0.45, green: 0.65, blue: 1), .white]
        case .gold:
            return [RGB(red: 1, green: 0.85, blue: 0.55), RGB(red: 1, green: 0.75, blue: 0.4), .white]
        }
    }

    private static func makeBackground(width: Int, height: Int, nebula: Bool, rng: inout SeededGenerator) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: VideoEncoder.colorSpace,
            bitmapInfo: VideoEncoder.bitmapInfo
        ) else { return nil }

        let w = Double(width)
        let h = Double(height)
        let space = VideoEncoder.colorSpace
        let locations: [CGFloat] = [0, 1]

        let sky = [RGB(red: 0.008, green: 0.01, blue: 0.035).cgColor(), RGB(red: 0.02, green: 0.025, blue: 0.08).cgColor()]
        if let gradient = CGGradient(colorsSpace: space, colors: sky as CFArray, locations: locations) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])
        }

        if nebula {
            let hues = [
                RGB(red: 0.45, green: 0.18, blue: 0.75),
                RGB(red: 0.1, green: 0.35, blue: 0.8),
                RGB(red: 0.75, green: 0.15, blue: 0.45),
                RGB(red: 0.05, green: 0.55, blue: 0.6),
            ]
            for _ in 0..<6 {
                let hue = hues[Int.random(in: 0..<hues.count, using: &rng)]
                let center = CGPoint(x: Double.random(in: 0...w, using: &rng), y: Double.random(in: 0...h, using: &rng))
                let radius = Double.random(in: 0.25...0.6, using: &rng) * max(w, h)
                let alpha = Double.random(in: 0.06...0.16, using: &rng)
                let colors = [hue.cgColor(alpha: alpha), hue.cgColor(alpha: 0)]
                if let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations) {
                    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
                }
            }
        }

        // Distant, motionless stars.
        let scale = Double(min(width, height)) / 1080
        let distantCount = Int(w * h / 1_000_000 * 180)
        for _ in 0..<distantCount {
            let size = Double.random(in: 0.5...1.6, using: &rng) * scale
            let brightness = Double.random(in: 0.15...0.7, using: &rng)
            context.setFillColor(RGB.white.cgColor(alpha: brightness))
            context.fillEllipse(in: CGRect(
                x: Double.random(in: 0...w, using: &rng),
                y: Double.random(in: 0...h, using: &rng),
                width: size,
                height: size
            ))
        }
        return context.makeImage()
    }
}
