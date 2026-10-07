import AppKit
import CoreGraphics

struct DisplayInfo: Identifiable, Hashable, Sendable {
    /// Stable across reboots and reconnects (vendor/model/serial).
    let id: String
    let displayID: CGDirectDisplayID
    let name: String
    let pixelWidth: Int
    let pixelHeight: Int
    let isMain: Bool

    @MainActor
    init(screen: NSScreen) {
        displayID = screen.displayID
        id = screen.stableID
        name = screen.localizedName
        pixelWidth = Int((screen.frame.width * screen.backingScaleFactor).rounded())
        pixelHeight = Int((screen.frame.height * screen.backingScaleFactor).rounded())
        isMain = screen == NSScreen.screens.first
    }

    var resolutionLabel: String { "\(pixelWidth) × \(pixelHeight)" }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Identifier that survives reconnects, unlike `CGDirectDisplayID`.
    var stableID: String {
        let id = displayID
        let vendor = CGDisplayVendorNumber(id)
        let model = CGDisplayModelNumber(id)
        let serial = CGDisplaySerialNumber(id)
        if serial != 0 {
            return "\(vendor)-\(model)-\(serial)"
        }
        // Displays without a serial number (common for built-in panels and some adapters).
        return "\(vendor)-\(model)-unit\(CGDisplayUnitNumber(id))"
    }

    /// Native pixel size of the screen.
    var pixelSize: CGSize {
        CGSize(width: frame.width * backingScaleFactor, height: frame.height * backingScaleFactor)
    }
}
