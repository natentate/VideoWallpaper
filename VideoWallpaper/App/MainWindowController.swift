import AppKit
import SwiftUI

/// Owns the library window. It is managed manually (instead of a SwiftUI `Window` scene) so the app can
/// start silently at login and live in the menu bar, only showing a Dock icon while the window is open.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?

    func show(section: SidebarItem? = nil) {
        if let section {
            AppModel.shared.selectedSection = section
        }
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: RootView())
        hosting.sizingOptions = [.minSize]

        let window = NSWindow(contentViewController: hosting)
        window.title = "VideoWallpaper"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 960, height: 620)
        window.setContentSize(NSSize(width: 1200, height: 780))
        window.center()
        window.setFrameAutosaveName("VideoWallpaperMainWindow")
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        if Preferences.shared.hideDockIconWhenClosed {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
