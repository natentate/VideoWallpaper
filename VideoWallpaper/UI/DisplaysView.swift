import SwiftUI

struct DisplaysView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(title: "Now Playing", subtitle: model.statusText) {
                    HStack(spacing: 10) {
                        Button {
                            model.togglePause()
                        } label: {
                            Label(model.state.isPaused ? "Resume" : "Pause", systemImage: model.state.isPaused ? "play.fill" : "pause.fill")
                        }
                        Button {
                            model.next()
                        } label: {
                            Label("Next", systemImage: "forward.fill")
                        }
                        .disabled(library.wallpapers.count < 2)
                    }
                    .controlSize(.large)
                }

                if let focus = model.activeFocusDescription {
                    HStack(spacing: 10) {
                        Image(systemName: "moon.fill").foregroundStyle(.purple)
                        Text("Focus wallpaper active: **\(focus)**")
                        Spacer()
                        Button("Return to Regular Wallpaper") { model.deactivateFocus(nil) }
                    }
                    .card()
                }

                if model.displays.count > 1 {
                    Toggle("Use the same wallpaper on every display", isOn: Binding(
                        get: { model.state.sameOnAllDisplays },
                        set: { model.setSameOnAllDisplays($0) }
                    ))
                    .toggleStyle(.switch)
                }

                if model.state.sameOnAllDisplays || model.displays.count <= 1 {
                    DisplayCard(
                        title: model.displays.count > 1 ? "All Displays" : (model.displays.first?.name ?? "Display"),
                        subtitle: model.displays.map(\.resolutionLabel).joined(separator: "  ·  "),
                        displayID: model.displays.first?.id
                    )
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 20)], spacing: 20) {
                        ForEach(model.displays) { display in
                            DisplayCard(
                                title: display.name,
                                subtitle: display.resolutionLabel + (display.isMain ? " · Main display" : ""),
                                displayID: display.id
                            )
                        }
                    }
                }

                if library.wallpapers.isEmpty {
                    Button {
                        model.selectedSection = .create
                    } label: {
                        Label("Create your first wallpaper", systemImage: "wand.and.stars")
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
    }
}

private struct DisplayCard: View {
    let title: String
    let subtitle: String
    /// The display whose wallpaper is shown/edited. With "same on all displays" any display works.
    let displayID: String?

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: LibraryStore

    private var playing: Wallpaper? {
        displayID.flatMap { model.nowPlaying[$0] }.flatMap { library.wallpaper(id: $0) }
    }

    private var selection: Binding<UUID?> {
        Binding(
            get: { displayID.flatMap { model.baseWallpaperID(for: $0) } },
            set: { newValue in
                guard let newValue else {
                    model.clearWallpaper()
                    return
                }
                let target = model.state.sameOnAllDisplays ? nil : displayID
                model.setWallpaper(newValue, on: target)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WidescreenFrame(cornerRadius: 12) {
                if let playing {
                    LocalThumbnail(url: playing.thumbnailURL)
                } else {
                    ZStack {
                        Color.black.opacity(0.4)
                        VStack(spacing: 6) {
                            Image(systemName: "display")
                                .font(.largeTitle)
                            Text("System wallpaper")
                                .font(.callout)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: 720)
            .shadow(color: .black.opacity(0.2), radius: 10, y: 5)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.title3.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    if let playing {
                        Text([playing.name, playing.resolutionLabel].compactMap { $0 }.joined(separator: " · "))
                            .font(.callout)
                            .padding(.top, 2)
                    }
                }
                Spacer()
                WallpaperPicker(title: "Wallpaper", selection: selection, noneLabel: "None (system wallpaper)")
                    .frame(maxWidth: 280)
            }
        }
        .card()
    }
}
