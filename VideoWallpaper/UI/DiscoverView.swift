import AVKit
import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var discover: DiscoverModel
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var downloads: DownloadManager
    @State private var previewing: RemoteVideo?

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 18)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: "Discover", subtitle: "Download free high-resolution video wallpapers, or generate one locally.")

                categoryStrip
                searchBar

                if discover.source.requiresAPIKey && !preferences.isConfigured(discover.source) {
                    APIKeyCard(source: discover.source)
                }

                if let category = discover.selectedCategory, let generator = category.generator {
                    GeneratorCallout(kind: generator)
                }

                if !downloads.items.isEmpty {
                    DownloadsPanel()
                }

                results
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .task {
            // Show something on first visit instead of an empty page.
            if !discover.hasSearched, let first = discover.categories.first(where: { $0.id == "deep-space" }) ?? discover.categories.first {
                discover.select(first)
            }
        }
        .sheet(item: $previewing) { video in
            RemotePreviewSheet(video: video)
                .environmentObject(discover)
                .environmentObject(preferences)
                .environmentObject(downloads)
                .environmentObject(LibraryStore.shared)
                .environmentObject(model)
        }
    }

    // MARK: Categories

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(discover.categories) { category in
                    CategoryTile(category: category, isSelected: discover.selectedCategoryID == category.id) {
                        discover.select(category)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: 12) {
            Picker("Source", selection: $discover.source) {
                ForEach(VideoSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 250)
            .onChange(of: discover.source) {
                discover.sourceChanged()
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search \(discover.source.title) — try “matrix”, “rain on window”, “spacex”", text: $discover.query)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        discover.selectedCategoryID = nil
                        discover.search()
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            if discover.source != .nasa {
                Toggle("4K only", isOn: $discover.only4K)
                    .toggleStyle(.checkbox)
                    .onChange(of: discover.only4K) {
                        if discover.hasSearched { discover.search() }
                    }
            }

            Button("Search") {
                discover.selectedCategoryID = nil
                discover.search()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        if let error = discover.errorMessage, discover.results.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load videos", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                if discover.source.requiresAPIKey {
                    Button("Open Settings") { model.selectedSection = .settings }
                }
            }
            .padding(.top, 30)
        } else if discover.results.isEmpty && discover.isLoading {
            ProgressView("Searching \(discover.source.title)…")
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else if discover.results.isEmpty && discover.hasSearched {
            ContentUnavailableView.search(text: discover.query)
                .padding(.top, 30)
        } else if !discover.hasSearched {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pick a category above or search for anything.")
                    .font(.title3.weight(.medium))
                Text("Videos come from \(VideoSource.allCases.map(\.title).joined(separator: ", ")). Pexels and Pixabay need a free API key (Settings › Online Sources); NASA works out of the box.")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(discover.results) { video in
                        RemoteVideoCard(video: video) {
                            previewing = video
                        }
                    }
                }
                HStack {
                    Link(discover.source.attribution, destination: discover.source.homepage)
                        .font(.caption)
                    Spacer()
                    if discover.hasMore {
                        Button {
                            discover.loadMore()
                        } label: {
                            if discover.isLoading {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Load More")
                            }
                        }
                        .disabled(discover.isLoading)
                    }
                }
            }
        }
    }
}

private struct CategoryTile: View {
    let category: CatalogCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: category.symbol)
                    .font(.system(size: 20, weight: .semibold))
                Spacer(minLength: 0)
                Text(category.title)
                    .font(.callout.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .padding(12)
            .frame(width: 128, height: 92, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: category.colors.map { Color(hex: $0) },
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.white : Color.white.opacity(0.1), lineWidth: isSelected ? 2.5 : 1)
            )
            .shadow(color: .black.opacity(isSelected ? 0.35 : 0.15), radius: isSelected ? 8 : 4, y: 3)
        }
        .buttonStyle(.plain)
    }
}

private struct GeneratorCallout: View {
    let kind: GeneratorKind
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "wand.and.stars")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Make it yourself: \(kind.title)").font(.headline)
                Text("Render a perfectly looping \(kind.title.lowercased()) wallpaper at your display's native resolution — no download needed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Generator") {
                CreateView.pendingKind = kind
                model.selectedSection = .create
            }
            .buttonStyle(.borderedProminent)
        }
        .card()
    }
}

struct APIKeyCard: View {
    let source: VideoSource
    @EnvironmentObject private var preferences: Preferences
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Connect \(source.title) — it's free", systemImage: "key.fill")
                .font(.headline)
            Text("\(source.tagline) Create an account, copy your API key and paste it here.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                SecureField("\(source.title) API key", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                Button("Save") {
                    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
                    switch source {
                    case .pexels: preferences.pexelsAPIKey = trimmed
                    case .pixabay: preferences.pixabayAPIKey = trimmed
                    case .nasa: break
                    }
                }
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let url = source.apiKeyURL {
                    Link("Get a free key…", destination: url)
                }
            }
        }
        .card()
    }
}

struct RemoteVideoCard: View {
    let video: RemoteVideo
    let onPreview: () -> Void

    @EnvironmentObject private var discover: DiscoverModel
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var model: AppModel
    @State private var isHovering = false

    private var libraryItem: Wallpaper? { library.wallpaper(remoteID: video.id) }
    private var download: DownloadItem? { downloads.item(forRemoteID: video.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidescreenFrame(cornerRadius: 12) {
                ZStack {
                    AsyncImage(url: video.thumbnailURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .failure:
                            Image(systemName: "photo").foregroundStyle(.secondary)
                        default:
                            ProgressView().controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.35))

                    if isHovering && libraryItem == nil && download?.isActive != true {
                        Color.black.opacity(0.35)
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 4) {
                    if let resolution = video.resolutionLabel {
                        Pill(text: resolution)
                    }
                    if let duration = video.duration, duration > 0 {
                        Pill(text: Wallpaper.durationLabel(duration))
                    }
                }
                .padding(8)
            }
            .overlay(alignment: .bottom) {
                if let download, download.isActive {
                    ProgressView(value: download.fraction ?? 0)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .padding(10)
                }
            }
            .shadow(color: .black.opacity(isHovering ? 0.3 : 0.15), radius: isHovering ? 12 : 6, y: 4)
            .onTapGesture(perform: onPreview)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(video.author.map { "by \($0)" } ?? video.source.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                actionButton
            }
            .padding(.horizontal, 2)
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }

    @ViewBuilder
    private var actionButton: some View {
        if let libraryItem {
            Button("Set") { model.setWallpaper(libraryItem.id) }
                .help("Play this wallpaper")
        } else if let download, download.isActive {
            Button {
                downloads.cancel(download.id)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Cancel download")
        } else {
            Button {
                Task { await discover.download(video, setWhenFinished: true) }
            } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .help("Download and set as wallpaper")
        }
    }
}

struct DownloadsPanel: View {
    @EnvironmentObject private var downloads: DownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Downloads").font(.headline)
                Spacer()
                if downloads.items.contains(where: { !$0.isActive }) {
                    Button("Clear Completed") { downloads.clearCompleted() }
                        .buttonStyle(.borderless)
                }
            }
            ForEach(downloads.items) { item in
                HStack(spacing: 12) {
                    statusIcon(item)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.request.title).lineLimit(1)
                        if item.phase == .downloading {
                            if let fraction = item.fraction {
                                ProgressView(value: fraction)
                            } else {
                                ProgressView().progressViewStyle(.linear)
                            }
                        }
                        Text(item.progressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    if item.isActive {
                        Button {
                            downloads.cancel(item.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(item.phase == .processing)
                    } else {
                        Button {
                            downloads.dismiss(item.id)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private func statusIcon(_ item: DownloadItem) -> some View {
        switch item.phase {
        case .downloading: Image(systemName: "arrow.down.circle").foregroundStyle(.blue)
        case .processing: ProgressView().controlSize(.small)
        case .finished: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}

struct RemotePreviewSheet: View {
    @State var video: RemoteVideo

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var discover: DiscoverModel
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var model: AppModel
    @State private var player: AVPlayer?
    @State private var selectedFileID: String?
    @State private var errorMessage: String?
    @State private var isResolving = false

    private var selectedFile: RemoteVideoFile? {
        video.files.first { $0.id == selectedFileID } ?? video.preferredFile(for: preferences.downloadQuality)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WidescreenFrame(cornerRadius: 12) {
                ZStack {
                    Color.black
                    if let player {
                        VideoPlayer(player: player)
                    } else if isResolving {
                        ProgressView().controlSize(.large)
                    } else {
                        AsyncImage(url: video.thumbnailURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            ProgressView()
                        }
                    }
                }
            }
            .frame(width: 720)

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title).font(.title2.weight(.semibold)).lineLimit(2)
                HStack(spacing: 6) {
                    Text(video.author.map { "by \($0) · \(video.source.title)" } ?? video.source.title)
                    if let page = video.pageURL {
                        Link("View on \(video.source.title)", destination: page)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 12) {
                if !video.files.isEmpty {
                    Picker("Quality", selection: Binding(
                        get: { selectedFile?.id },
                        set: { selectedFileID = $0 }
                    )) {
                        ForEach(video.files) { file in
                            Text(file.displayName).tag(String?.some(file.id))
                        }
                    }
                    .frame(maxWidth: 360)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if let existing = library.wallpaper(remoteID: video.id) {
                    Button("Set as Wallpaper") {
                        model.setWallpaper(existing.id)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Download") {
                        startDownload(setWhenFinished: false)
                    }
                    .disabled(selectedFile == nil)
                    Button("Download & Set") {
                        startDownload(setWhenFinished: true)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedFile == nil)
                }
            }
        }
        .padding(22)
        .frame(width: 764)
        .task {
            await prepare()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private func prepare() async {
        if video.files.isEmpty {
            isResolving = true
            do {
                video = try await discover.resolveFiles(for: video)
            } catch {
                errorMessage = error.localizedDescription
            }
            isResolving = false
        }
        guard let preview = video.previewFile else { return }
        let player = AVPlayer(url: preview.url)
        player.isMuted = true
        self.player = player
        player.play()
    }

    private func startDownload(setWhenFinished: Bool) {
        let file = selectedFile
        let video = self.video
        Task {
            await discover.download(video, file: file, setWhenFinished: setWhenFinished)
        }
        dismiss()
    }
}
