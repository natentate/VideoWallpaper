import SwiftUI

@main
struct VideoWallpaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra("VideoWallpaper", systemImage: model.state.isPaused ? "pause.rectangle" : "play.rectangle.on.rectangle") {
            MenuBarContent()
                .environmentObject(AppModel.shared)
                .environmentObject(LibraryStore.shared)
        }
        .menuBarExtraStyle(.menu)
    }
}
