import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    enum Scope {
        case all
        case favorites
    }

    let scope: Scope

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: LibraryStore
    @State private var searchText = ""
    @State private var originFilter: Wallpaper.Origin?
    @State private var isImporting = false
    @State private var isDropTargeted = false
    @State private var renameTarget: Wallpaper?
    @State private var renameText = ""
    @State private var deleteTarget: Wallpaper?

    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 360), spacing: 18)]

    private var filtered: [Wallpaper] {
        library.wallpapers.filter { wallpaper in
            (scope == .all || wallpaper.isFavorite)
                && (originFilter == nil || wallpaper.origin == originFilter)
                && (searchText.isEmpty || wallpaper.name.localizedCaseInsensitiveContains(searchText)
                    || (wallpaper.provider ?? "").localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(
                title: scope == .all ? "Library" : "Favorites",
                subtitle: scope == .all
                    ? "Double-click a wallpaper to play it. Drop video files here to add your own."
                    : "Your favorite wallpapers. Auto-rotation can cycle through just these."
            ) {
                Button {
                    isImporting = true
                } label: {
                    Label("Add Your Own Video…", systemImage: "plus")
                }
                .controlSize(.large)
            }

            if !library.wallpapers.isEmpty {
                filterBar
            }

            if library.wallpapers.isEmpty {
                EmptyLibraryView(isImporting: $isImporting)
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    scope == .favorites ? "No Favorites Yet" : "No Matches",
                    systemImage: scope == .favorites ? "heart" : "magnifyingglass",
                    description: Text(scope == .favorites ? "Click the heart on any wallpaper to add it here." : "Try a different search or filter.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(filtered) { wallpaper in
                            WallpaperCard(
                                wallpaper: wallpaper,
                                onRename: {
                                    renameText = wallpaper.name
                                    renameTarget = wallpaper
                                },
                                onDelete: { deleteTarget = wallpaper }
                            )
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        Label("Drop videos to add them", systemImage: "square.and.arrow.down")
                            .font(.title2.weight(.semibold))
                    }
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let videos = urls.filter { $0.isFileURL }
            guard !videos.isEmpty else { return false }
            model.importFiles(videos)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                model.importFiles(urls)
            }
        }
        .alert("Rename Wallpaper", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let target = renameTarget {
                    library.rename(target.id, to: renameText)
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .confirmationDialog(
            "Delete “\(deleteTarget?.name ?? "")”?",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let target = deleteTarget {
                    model.deleteWallpapers([target.id])
                }
                deleteTarget = nil
            }
        } message: {
            Text("The video file is removed from VideoWallpaper's library. Original files you imported are not touched.")
        }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search wallpapers", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 320)

            Picker("Source", selection: $originFilter) {
                Text("All").tag(Wallpaper.Origin?.none)
                ForEach(Wallpaper.Origin.allCases, id: \.self) { origin in
                    Text(origin.label).tag(Wallpaper.Origin?.some(origin))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 380)

            Spacer()
            Text("\(filtered.count) wallpaper\(filtered.count == 1 ? "" : "s")")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct WallpaperCard: View {
    let wallpaper: Wallpaper
    var onRename: () -> Void
    var onDelete: () -> Void

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: LibraryStore
    @State private var isHovering = false

    private var playingOn: [DisplayInfo] {
        model.displays.filter { model.nowPlaying[$0.id] == wallpaper.id }
    }

    private var playingLabel: String {
        guard model.displays.count > 1 else { return "Now Playing" }
        if playingOn.count == model.displays.count { return "Playing on all displays" }
        return "Playing on " + playingOn.map(\.name).joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidescreenFrame(cornerRadius: 12) {
                ZStack {
                    LocalThumbnail(url: wallpaper.thumbnailURL)
                    if isHovering {
                        Color.black.opacity(0.35)
                        Button {
                            model.setWallpaper(wallpaper.id)
                        } label: {
                            Label("Set as Wallpaper", systemImage: "play.fill")
                                .font(.callout.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 4) {
                    if let resolution = wallpaper.resolutionLabel {
                        Pill(text: resolution)
                    }
                    if let duration = wallpaper.durationLabel {
                        Pill(text: duration)
                    }
                }
                .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    library.toggleFavorite(wallpaper.id)
                } label: {
                    Image(systemName: wallpaper.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(wallpaper.isFavorite ? Color.pink : Color.white)
                        .padding(7)
                        .background(.black.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)
                .opacity(isHovering || wallpaper.isFavorite ? 1 : 0)
                .padding(6)
                .help(wallpaper.isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }
            .overlay(alignment: .bottomLeading) {
                if !playingOn.isEmpty {
                    Pill(text: playingLabel, systemImage: "play.fill", tint: Color.accentColor.opacity(0.9))
                        .padding(8)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(playingOn.isEmpty ? Color.clear : Color.accentColor, lineWidth: 2.5)
            }
            .shadow(color: .black.opacity(isHovering ? 0.3 : 0.15), radius: isHovering ? 12 : 6, y: 4)
            .onTapGesture(count: 2) {
                model.setWallpaper(wallpaper.id)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(wallpaper.name)
                    .font(.headline)
                    .lineLimit(1)
                Text([wallpaper.sourceLabel, wallpaper.author].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .contextMenu { contextMenu }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Set on All Displays") { model.setWallpaper(wallpaper.id) }
        if model.displays.count > 1 {
            Menu("Set on Display") {
                ForEach(model.displays) { display in
                    Button(display.name) { model.setWallpaper(wallpaper.id, on: display.id) }
                }
            }
        }
        Menu("Use for Focus") {
            ForEach(model.state.focusProfiles) { profile in
                Button {
                    model.updateFocusProfile(profile.id) { $0.wallpaperID = wallpaper.id }
                } label: {
                    if profile.wallpaperID == wallpaper.id {
                        Label(profile.name, systemImage: "checkmark")
                    } else {
                        Text(profile.name)
                    }
                }
            }
        }
        Divider()
        Button(wallpaper.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
            library.toggleFavorite(wallpaper.id)
        }
        Button("Rename…", action: onRename)
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([wallpaper.fileURL])
        }
        if let page = wallpaper.pageURL {
            Button("Open Source Page") { NSWorkspace.shared.open(page) }
        }
        Divider()
        Button("Delete…", role: .destructive, action: onDelete)
    }
}

struct EmptyLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isImporting: Bool

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("Your library is empty")
                    .font(.title2.weight(.semibold))
                Text("Generate a wallpaper right now, download one, or add your own video.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                startButton("Generate Matrix Code", symbol: "chevron.left.forwardslash.chevron.right") {
                    model.selectedSection = .create
                }
                startButton("Browse Online", symbol: "globe") {
                    model.selectedSection = .discover
                }
                startButton("Add Your Own Video", symbol: "plus") {
                    isImporting = true
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func startButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 24))
                Text(title)
                    .font(.callout.weight(.medium))
            }
            .frame(width: 170, height: 96)
        }
        .buttonStyle(.bordered)
    }
}
