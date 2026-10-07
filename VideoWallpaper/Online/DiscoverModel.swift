import Foundation

@MainActor
final class DiscoverModel: ObservableObject {
    @Published var source: VideoSource = .pexels
    @Published var query = ""
    @Published var only4K = false
    @Published var selectedCategoryID: String?
    @Published private(set) var categories: [CatalogCategory] = CatalogCategory.builtIn
    @Published private(set) var results: [RemoteVideo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasMore = false
    @Published private(set) var hasSearched = false

    private var page = 1
    private var generation = 0
    private var bootstrapped = false

    private var preferences: Preferences { Preferences.shared }

    var selectedCategory: CatalogCategory? {
        categories.first { $0.id == selectedCategoryID }
    }

    func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true
        source = [VideoSource.pexels, .pixabay].first { preferences.isConfigured($0) } ?? .nasa
        if let cached = CatalogLoader.cached() {
            categories = cached
        }
        let catalogURL = preferences.catalogURL
        Task {
            if let remote = await CatalogLoader.fetch(from: catalogURL) {
                categories = remote
            }
        }
    }

    func select(_ category: CatalogCategory) {
        selectedCategoryID = category.id
        if category.query(for: source) == nil || !preferences.isConfigured(source) {
            source = category.preferredSource(preferences: preferences)
        }
        query = category.query(for: source) ?? category.title
        search()
    }

    func search() {
        page = 1
        results = []
        hasMore = false
        load()
    }

    func loadMore() {
        guard hasMore, !isLoading else { return }
        page += 1
        load()
    }

    func sourceChanged() {
        if let category = selectedCategory {
            query = category.query(for: source) ?? category.title
        }
        if hasSearched || !query.isEmpty {
            search()
        } else {
            results = []
            errorMessage = nil
        }
    }

    private func makeProvider() -> VideoSearchProvider {
        switch source {
        case .pexels: return PexelsProvider(apiKey: preferences.apiKey(for: .pexels))
        case .pixabay: return PixabayProvider(apiKey: preferences.apiKey(for: .pixabay))
        case .nasa: return NASAProvider()
        }
    }

    private func load() {
        generation += 1
        let token = generation
        let provider = makeProvider()
        let query = self.query
        let page = self.page
        let only4K = self.only4K
        isLoading = true
        errorMessage = nil
        hasSearched = true
        Task {
            do {
                let result = try await provider.search(query: query, page: page, only4K: only4K)
                guard token == generation else { return }
                let known = Set(results.map(\.id))
                results += result.videos.filter { !known.contains($0.id) }
                hasMore = result.hasMore && !result.videos.isEmpty
            } catch {
                guard token == generation else { return }
                errorMessage = error.localizedDescription
                hasMore = false
            }
            isLoading = false
        }
    }

    /// NASA items list their files in a separate manifest; resolve on demand.
    func resolveFiles(for video: RemoteVideo) async throws -> RemoteVideo {
        guard video.files.isEmpty, let manifest = video.manifestURL else { return video }
        let files = try await NASAProvider.resolveFiles(manifest: manifest)
        guard !files.isEmpty else { throw ProviderError.noDownloadableFile }
        var resolved = video
        resolved.files = files
        if let index = results.firstIndex(where: { $0.id == video.id }) {
            results[index] = resolved
        }
        return resolved
    }

    func download(_ video: RemoteVideo, file: RemoteVideoFile? = nil, setWhenFinished: Bool) async {
        do {
            let resolved = try await resolveFiles(for: video)
            guard let file = file ?? resolved.preferredFile(for: preferences.downloadQuality) else {
                throw ProviderError.noDownloadableFile
            }
            DownloadManager.shared.start(DownloadRequest(
                remoteID: resolved.id,
                title: resolved.title,
                provider: resolved.source.title,
                author: resolved.author,
                pageURL: resolved.pageURL,
                thumbnailURL: resolved.thumbnailURL,
                fileURL: file.url,
                setWhenFinished: setWhenFinished
            ))
        } catch {
            AppModel.shared.showToast(error.localizedDescription, isError: true)
        }
    }
}
