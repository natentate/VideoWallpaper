import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemMessage: String?
    @State private var libraryBytes: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: "Settings")
                .padding(.horizontal, 28)
                .padding(.top, 14)

            Form {
                Section("General") {
                    Toggle("Open at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) {
                            updateLoginItem(launchAtLogin)
                        }
                    if let loginItemMessage {
                        Text(loginItemMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Hide Dock icon when the window is closed", isOn: $preferences.hideDockIconWhenClosed)
                    Toggle("Match the system wallpaper to the video", isOn: $preferences.syncDesktopPicture)
                    Text("Sets a still frame as your macOS wallpaper so Mission Control, Space switching and the lock screen match.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Playback") {
                    Picker("Scaling", selection: $preferences.scaling) {
                        ForEach(VideoScaling.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Crossfade between wallpapers", isOn: $preferences.crossfade)
                    Toggle("Pause when windows cover the desktop", isOn: $preferences.pauseWhenCovered)
                    Toggle("Pause on battery power", isOn: $preferences.pauseOnBattery)
                    Toggle("Pause in Low Power Mode", isOn: $preferences.pauseInLowPowerMode)
                    Text("Video always pauses while the screen is locked, the display sleeps or the screen saver runs. Videos are muted.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Auto-Change") {
                    Picker("Change wallpaper", selection: $preferences.rotationInterval) {
                        ForEach(RotationInterval.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Choose from", selection: $preferences.rotationSource) {
                        ForEach(RotationSource.allCases) { Text($0.title).tag($0) }
                    }
                    .disabled(preferences.rotationInterval == .off)
                    Text("Auto-change pauses while a Focus wallpaper is active.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Online Sources") {
                    apiKeyRow(source: .pexels, key: $preferences.pexelsAPIKey)
                    apiKeyRow(source: .pixabay, key: $preferences.pixabayAPIKey)
                    LabeledContent("NASA") {
                        Text("No key needed").foregroundStyle(.secondary)
                    }
                    Picker("Download quality", selection: $preferences.downloadQuality) {
                        ForEach(DownloadQuality.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Catalog URL", text: $preferences.catalogURL)
                    Text("Discover categories are loaded from this JSON file when available (falls back to the built-in list).")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Storage") {
                    LabeledContent("Library") {
                        Text("\(library.wallpapers.count) videos · \(libraryBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "…")")
                    }
                    LabeledContent("Location") {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([AppPaths.videos])
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    Text("Stock videos are provided by Pexels, Pixabay and NASA under their respective licenses. Matrix and Starfield wallpapers are rendered on your Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .task(id: library.wallpapers.count) {
            libraryBytes = library.wallpapers.reduce(Int64(0)) { $0 + ($1.fileSize ?? 0) }
        }
    }

    private func apiKeyRow(source: VideoSource, key: Binding<String>) -> some View {
        LabeledContent(source.title) {
            HStack {
                SecureField("API key", text: key)
                    .frame(maxWidth: 260)
                if let url = source.apiKeyURL {
                    Link("Get free key", destination: url)
                        .font(.caption)
                }
            }
        }
    }

    private func updateLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemMessage = SMAppService.mainApp.status == .requiresApproval
                ? "Approve VideoWallpaper in System Settings › General › Login Items."
                : nil
        } catch {
            loginItemMessage = "Couldn't update login item: \(error.localizedDescription)"
        }
    }
}
