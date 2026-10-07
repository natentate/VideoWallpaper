import CoreGraphics
import CoreText
import Foundation

/// Renders "digital rain": columns of mirrored katakana and digits falling cell by cell with glowing heads.
///
/// Every moving part is periodic in the loop length — each drop completes a whole number of passes
/// and each glyph flickers on a period that divides the frame count — so the last frame flows straight
/// back into the first.
final class MatrixRainRenderer: FrameRenderer {
    private struct Drop {
        let cycles: Int
        let phase: Double
        let trail: Int
    }

    private struct Column {
        let x: CGFloat
        let drops: [Drop]
    }

    private struct Layer {
        let cellHeight: CGFloat
        let rows: Int
        let columns: [Column]
        let atlas: GlyphAtlas
    }

    private static let glyphs: [String] = {
        let katakana = "ｦｱｳｴｵｶｷｹｺｻｼｽｾｿﾀﾂﾃﾅﾆﾇﾈﾊﾋﾎﾏﾐﾑﾒﾓﾔﾕﾗﾘﾜ"
        let digits = "0123456789"
        let symbols = "Z:.=*+-<>¦|"
        return (katakana + digits + symbols).map(String.init)
    }()

    private let width: Int
    private let height: Int
    private let totalFrames: Int
    private let seed: UInt64
    private let layers: [Layer]
    /// Glyph flicker periods (in frames) that divide `totalFrames`.
    private let periods: [Int]
    private let background = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)

    init(width: Int, height: Int, fps: Int, totalFrames: Int, settings: MatrixSettings, seed: UInt64) {
        self.width = width
        self.height = height
        self.totalFrames = max(1, totalFrames)
        self.seed = seed

        let frameCount = max(1, totalFrames)
        let divisors = (1...frameCount).filter { frameCount % $0 == 0 && $0 >= max(4, fps / 5) }
        periods = divisors.isEmpty ? [frameCount] : divisors

        var rng = SeededGenerator(seed: seed)
        let loopSeconds = Double(frameCount) / Double(max(fps, 1))
        let baseCell = (Double(height) / settings.glyphScale.rows).rounded()
        let color = settings.palette.color

        var layers: [Layer] = []
        if settings.depthLayer {
            layers.append(MatrixRainRenderer.makeLayer(
                width: width, height: height, cellHeight: max(6, (baseCell * 0.6).rounded()),
                brightness: 0.38, density: settings.density * 0.7, speed: settings.speed,
                loopSeconds: loopSeconds, color: color, mirrored: settings.mirroredGlyphs, rng: &rng
            ))
        }
        layers.append(MatrixRainRenderer.makeLayer(
            width: width, height: height, cellHeight: max(8, baseCell),
            brightness: 1, density: settings.density, speed: settings.speed,
            loopSeconds: loopSeconds, color: color, mirrored: settings.mirroredGlyphs, rng: &rng
        ))
        self.layers = layers
    }

    private static func makeLayer(
        width: Int,
        height: Int,
        cellHeight: Double,
        brightness: Double,
        density: Double,
        speed: RainSpeed,
        loopSeconds: Double,
        color: RGB,
        mirrored: Bool,
        rng: inout SeededGenerator
    ) -> Layer {
        let cellWidth = (cellHeight * 0.64).rounded()
        let rows = Int((Double(height) / cellHeight).rounded(.up))
        let columnCount = Int((Double(width) / cellWidth).rounded(.up))

        var columns: [Column] = []
        columns.reserveCapacity(columnCount)
        for index in 0..<columnCount {
            var drops: [Drop] = []
            let dropCount = 1 + (Double.random(in: 0..<1, using: &rng) < density ? 1 : 0)
            for _ in 0..<dropCount {
                let trail = Int.random(in: max(4, rows / 4)...max(5, rows * 4 / 5), using: &rng)
                let velocity = Double.random(in: speed.cellsPerSecond, using: &rng)
                let travel = Double(rows + trail)
                let cycles = max(1, Int((velocity * loopSeconds / travel).rounded()))
                drops.append(Drop(cycles: cycles, phase: Double.random(in: 0..<1, using: &rng), trail: trail))
            }
            columns.append(Column(x: CGFloat(index) * CGFloat(cellWidth), drops: drops))
        }

        let atlas = GlyphAtlas(
            glyphs: glyphs,
            cellSize: CGSize(width: cellWidth, height: cellHeight),
            color: color,
            brightness: brightness,
            levels: 8,
            mirrored: mirrored
        )
        return Layer(cellHeight: CGFloat(cellHeight), rows: rows, columns: columns, atlas: atlas)
    }

    func render(frame: Int, into context: CGContext) {
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .low

        let loopPosition = Double(frame % totalFrames) / Double(totalFrames)
        for (layerIndex, layer) in layers.enumerated() {
            let atlas = layer.atlas
            let glyphCount = atlas.count
            for (columnIndex, column) in layer.columns.enumerated() {
                for drop in column.drops {
                    var progress = Double(drop.cycles) * loopPosition + drop.phase
                    progress -= progress.rounded(.down)
                    let head = Int(progress * Double(layer.rows + drop.trail))
                    let lower = max(0, head - drop.trail + 1)
                    let upper = min(layer.rows - 1, head)
                    guard lower <= upper else { continue }

                    for row in lower...upper {
                        let age = head - row
                        let glyph = glyphIndex(layer: layerIndex, column: columnIndex, row: row, frame: frame, count: glyphCount)
                        let image: CGImage
                        if age == 0 {
                            image = atlas.heads[glyph]
                        } else {
                            let freshness = 1 - Double(age) / Double(drop.trail)
                            let level = min(atlas.levels - 1, max(0, Int(pow(freshness, 1.3) * Double(atlas.levels))))
                            image = atlas.images[level][glyph]
                        }
                        let y = CGFloat(height) - CGFloat(row + 1) * layer.cellHeight
                        context.draw(image, in: CGRect(
                            x: column.x - atlas.padding,
                            y: y - atlas.padding,
                            width: atlas.imageSize.width,
                            height: atlas.imageSize.height
                        ))
                    }
                }
            }
        }
    }

    @inline(__always)
    private func glyphIndex(layer: Int, column: Int, row: Int, frame: Int, count: Int) -> Int {
        let cell = hashMix(UInt64(layer), UInt64(column), UInt64(row), seed)
        // Roughly 40% of cells hold their glyph for the whole loop; the rest flicker at their own pace.
        let period = (cell & 0xFF) < 100 ? totalFrames : periods[Int((cell >> 8) % UInt64(periods.count))]
        let offset = Int((cell >> 24) % UInt64(period))
        let epoch = ((frame + offset) % totalFrames) / period
        return Int(hashMix(cell, UInt64(epoch), 0x51_7CC1_B727_220A) % UInt64(count))
    }
}

/// Pre-rendered glyph bitmaps at several brightness levels, so each frame is just image blits.
final class GlyphAtlas {
    let images: [[CGImage]]
    let heads: [CGImage]
    let levels: Int
    let padding: CGFloat
    let imageSize: CGSize

    var count: Int { heads.count }

    init(glyphs: [String], cellSize: CGSize, color: RGB, brightness: Double, levels: Int, mirrored: Bool) {
        let padding = (cellSize.height * 0.4).rounded()
        let imageSize = CGSize(width: cellSize.width + padding * 2, height: cellSize.height + padding * 2)
        self.levels = levels
        self.padding = padding
        self.imageSize = imageSize
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, cellSize.height * 0.8, nil)

        var images: [[CGImage]] = []
        for level in 0..<levels {
            let t = Double(level + 1) / Double(levels)
            let shade = color.scaled(0.22 + 0.78 * t).mixed(with: .white, amount: max(0, t - 0.8))
            let alpha = (0.2 + 0.8 * t) * brightness
            let glow = t > 0.55 ? cellSize.height * 0.3 * t : 0
            images.append(glyphs.map {
                GlyphAtlas.render($0, font: font, size: imageSize, color: shade.cgColor(alpha: alpha),
                            glowRadius: glow, glowColor: color.cgColor(alpha: 0.75 * brightness), mirrored: mirrored)
            })
        }
        self.images = images

        let headColor = color.mixed(with: .white, amount: 0.82)
        heads = glyphs.map {
            GlyphAtlas.render($0, font: font, size: imageSize, color: headColor.cgColor(alpha: brightness),
                        glowRadius: cellSize.height * 0.65, glowColor: color.cgColor(alpha: brightness), mirrored: mirrored)
        }
    }

    private static func render(
        _ glyph: String,
        font: CTFont,
        size: CGSize,
        color: CGColor,
        glowRadius: CGFloat,
        glowColor: CGColor,
        mirrored: Bool
    ) -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: VideoEncoder.colorSpace,
            bitmapInfo: VideoEncoder.bitmapInfo
        ) else {
            fatalError("Could not create glyph bitmap context")
        }
        if mirrored {
            context.translateBy(x: CGFloat(width), y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        if glowRadius > 0 {
            context.setShadow(offset: .zero, blur: glowRadius, color: glowColor)
        }
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: glyph, attributes: attributes))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        context.textPosition = CGPoint(
            x: ((CGFloat(width) - lineWidth) / 2).rounded(),
            y: ((CGFloat(height) - (ascent + descent)) / 2 + descent).rounded()
        )
        CTLineDraw(line, context)
        guard let image = context.makeImage() else {
            fatalError("Could not create glyph image")
        }
        return image
    }
}
