import AppKit

/// Optionally sets the macOS desktop picture to a still frame of the playing video, so Mission Control,
/// Space transitions and the login window match the live wallpaper.
@MainActor
enum DesktopPictureSync {
    private static var applied: [String: UUID] = [:]

    static func sync(nowPlaying: [String: UUID], library: LibraryStore) {
        for screen in NSScreen.screens {
            let displayID = screen.stableID
            guard let wallpaperID = nowPlaying[displayID],
                  applied[displayID] != wallpaperID,
                  let wallpaper = library.wallpaper(id: wallpaperID) else { continue }
            applied[displayID] = wallpaperID
            let pixelSize = screen.pixelSize
            Task { @MainActor in
                let still = wallpaper.stillURL
                if !FileManager.default.fileExists(atPath: still.path) {
                    do {
                        let image = try await Thumbnailer.frame(of: wallpaper.fileURL, maxSize: pixelSize, at: 0.5)
                        try Thumbnailer.writeJPEG(image.value, to: still, quality: 0.9)
                    } catch {
                        NSLog("VideoWallpaper: could not create still for \(wallpaper.name): \(error)")
                        return
                    }
                }
                guard let target = NSScreen.screens.first(where: { $0.stableID == displayID }) else { return }
                do {
                    try NSWorkspace.shared.setDesktopImageURL(still, for: target, options: [:])
                } catch {
                    NSLog("VideoWallpaper: could not set desktop picture: \(error)")
                }
            }
        }
    }

    static func reset() {
        applied.removeAll()
    }
}
