import SwiftUI

/// The menu shown from the menu bar icon.
struct MenuBarContent: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: LibraryStore

    private var nowPlayingTitle: String {
        let names = Set(model.nowPlaying.values).compactMap { library.wallpaper(id: $0)?.name }.sorted()
        if names.isEmpty { return "No video wallpaper" }
        return names.joined(separator: " · ")
    }

    var body: some View {
        Text(nowPlayingTitle)
        Text(model.statusText)
        if let focus = model.activeFocusDescription {
            Text("Focus: \(focus)")
        }

        Divider()

        Button(model.state.isPaused ? "Resume" : "Pause") {
            model.togglePause()
        }
        .keyboardShortcut("p")
        .disabled(model.nowPlaying.isEmpty)

        Button("Next Wallpaper") {
            model.next()
        }
        .keyboardShortcut("n")
        .disabled(library.wallpapers.count < 2)

        Menu("Set Wallpaper") {
            if !library.favorites.isEmpty {
                Section("Favorites") {
                    ForEach(library.favorites.prefix(15)) { wallpaper in
                        wallpaperButton(wallpaper)
                    }
                }
            }
            Section("Recent") {
                ForEach(library.wallpapers.filter { !$0.isFavorite }.prefix(15)) { wallpaper in
                    wallpaperButton(wallpaper)
                }
            }
        }
        .disabled(library.wallpapers.isEmpty)

        Menu("Focus Wallpaper") {
            ForEach(model.state.focusProfiles) { profile in
                Toggle(profile.name, isOn: Binding(
                    get: { model.isFocusActive(profile.id) },
                    set: { isOn in
                        if isOn {
                            model.activateFocus(profile.id)
                        } else {
                            model.deactivateFocus(profile.id)
                        }
                    }
                ))
            }
            Divider()
            Button("Return to Regular Wallpaper") { model.deactivateFocus(nil) }
                .disabled(model.state.activations.isEmpty)
            Button("Set Up Focus Modes…") { MainWindowController.shared.show(section: .focus) }
        }

        Divider()

        Button("Open Library…") { MainWindowController.shared.show(section: .library) }
            .keyboardShortcut("o")
        Button("Discover Wallpapers…") { MainWindowController.shared.show(section: .discover) }
        Button("Create Wallpaper…") { MainWindowController.shared.show(section: .create) }
        Button("Settings…") { MainWindowController.shared.show(section: .settings) }
            .keyboardShortcut(",")

        Divider()

        Button("Quit VideoWallpaper") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func wallpaperButton(_ wallpaper: Wallpaper) -> some View {
        let isPlaying = model.nowPlaying.values.contains(wallpaper.id)
        return Button {
            model.setWallpaper(wallpaper.id)
        } label: {
            if isPlaying {
                Label(wallpaper.name, systemImage: "checkmark")
            } else {
                Text(wallpaper.name)
            }
        }
    }
}
