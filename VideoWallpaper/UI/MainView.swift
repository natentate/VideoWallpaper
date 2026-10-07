import SwiftUI

struct RootView: View {
    var body: some View {
        MainView()
            .environmentObject(AppModel.shared)
            .environmentObject(LibraryStore.shared)
            .environmentObject(Preferences.shared)
            .environmentObject(DownloadManager.shared)
            .environmentObject(GeneratorService.shared)
            .environmentObject(AppModel.shared.discover)
            .frame(minWidth: 960, minHeight: 620)
    }
}

struct MainView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 224)
            Divider()
                .ignoresSafeArea()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { model.toast = nil }
            }
        }
        .animation(.spring(duration: 0.35), value: model.toast)
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selectedSection ?? .library {
        case .displays: DisplaysView()
        case .library: LibraryView(scope: .all)
        case .favorites: LibraryView(scope: .favorites)
        case .discover: DiscoverView()
        case .create: CreateView()
        case .focus: FocusModesView()
        case .settings: SettingsView()
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloads: DownloadManager

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $model.selectedSection) {
                Section("Wallpapers") {
                    row(.displays)
                    row(.library)
                        .badge(library.wallpapers.count)
                    row(.favorites)
                }
                Section("Get More") {
                    row(.discover)
                        .badge(downloads.activeCount)
                    row(.create)
                }
                Section("Automation") {
                    row(.focus)
                }
                Section {
                    row(.settings)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            NowPlayingFooter()
                .padding(12)
        }
        .background(VisualEffectBackground(material: .sidebar).ignoresSafeArea())
    }

    private func row(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.symbol)
            .tag(item)
    }
}

/// Compact "now playing" card with a pause button at the bottom of the sidebar.
struct NowPlayingFooter: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: LibraryStore

    private var currentWallpaper: Wallpaper? {
        let mainID = model.displays.first(where: \.isMain)?.id ?? model.displays.first?.id
        return mainID.flatMap { model.nowPlaying[$0] }.flatMap { library.wallpaper(id: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let wallpaper = currentWallpaper {
                WidescreenFrame(cornerRadius: 8) {
                    LocalThumbnail(url: wallpaper.thumbnailURL)
                }
                Text(wallpaper.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(model.isPlaybackBlocked || model.nowPlaying.isEmpty ? Color.orange : Color.green)
                    .frame(width: 7, height: 7)
                Text(model.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 4)
                if !model.nowPlaying.isEmpty {
                    Button {
                        model.togglePause()
                    } label: {
                        Image(systemName: model.state.isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.borderless)
                    .help(model.state.isPaused ? "Resume" : "Pause")
                    Button {
                        model.next()
                    } label: {
                        Image(systemName: "forward.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Next wallpaper")
                }
            }
            if let focus = model.activeFocusDescription {
                Label("Focus: \(focus)", systemImage: "moon.fill")
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
