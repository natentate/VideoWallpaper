import Foundation

/// A themed collection in Discover. Each category maps to a search query per source and
/// optionally to a built-in generator that renders the theme locally (no download needed).
struct CatalogCategory: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let symbol: String
    /// Two hex colors for the tile gradient.
    let colors: [String]
    let pexels: String?
    let pixabay: String?
    let nasa: String?
    let generator: GeneratorKind?

    func query(for source: VideoSource) -> String? {
        switch source {
        case .pexels: return pexels
        case .pixabay: return pixabay
        case .nasa: return nasa
        }
    }

    /// The best source for this category given which API keys are configured.
    @MainActor
    func preferredSource(preferences: Preferences) -> VideoSource {
        for source in [VideoSource.pexels, .pixabay, .nasa] where query(for: source) != nil && preferences.isConfigured(source) {
            return source
        }
        return query(for: .nasa) != nil ? .nasa : .pexels
    }

    static let builtIn: [CatalogCategory] = [
        CatalogCategory(id: "matrix", title: "Matrix Code", symbol: "chevron.left.forwardslash.chevron.right", colors: ["#00140A", "#00C853"],
                        pexels: "matrix code", pixabay: "matrix code", nasa: nil, generator: .matrix),
        CatalogCategory(id: "deep-space", title: "Deep Space", symbol: "sparkles", colors: ["#05040F", "#3B1C7A"],
                        pexels: "galaxy stars space", pixabay: "galaxy space", nasa: "galaxy", generator: .starfield),
        CatalogCategory(id: "rain-window", title: "Rain on a Window", symbol: "cloud.rain.fill", colors: ["#0B1622", "#3E6A8A"],
                        pexels: "rain on window", pixabay: "rain window", nasa: nil, generator: nil),
        CatalogCategory(id: "spacex", title: "SpaceX & Launches", symbol: "flame.fill", colors: ["#120A05", "#E8590C"],
                        pexels: "rocket launch", pixabay: "rocket launch", nasa: "spacex launch", generator: nil),
        CatalogCategory(id: "earth-orbit", title: "Earth from Orbit", symbol: "globe.americas.fill", colors: ["#020A18", "#1565C0"],
                        pexels: "earth from space", pixabay: "earth space", nasa: "earth views from space station", generator: nil),
        CatalogCategory(id: "nebula", title: "Nebulae", symbol: "moon.stars.fill", colors: ["#12041C", "#C2185B"],
                        pexels: "nebula", pixabay: "nebula", nasa: "nebula", generator: nil),
        CatalogCategory(id: "aurora", title: "Northern Lights", symbol: "wand.and.rays", colors: ["#03140F", "#26A69A"],
                        pexels: "aurora borealis", pixabay: "aurora borealis", nasa: "aurora", generator: nil),
        CatalogCategory(id: "ocean", title: "Ocean Waves", symbol: "water.waves", colors: ["#021B26", "#0097A7"],
                        pexels: "ocean waves", pixabay: "ocean waves", nasa: nil, generator: nil),
        CatalogCategory(id: "city-night", title: "City at Night", symbol: "building.2.fill", colors: ["#0D0A1A", "#7E57C2"],
                        pexels: "city night timelapse", pixabay: "city night", nasa: nil, generator: nil),
        CatalogCategory(id: "neon", title: "Neon & Cyberpunk", symbol: "bolt.fill", colors: ["#14001F", "#FF00A8"],
                        pexels: "neon cyberpunk", pixabay: "neon", nasa: nil, generator: nil),
        CatalogCategory(id: "forest", title: "Forest & Nature", symbol: "leaf.fill", colors: ["#06140A", "#43A047"],
                        pexels: "forest", pixabay: "forest", nasa: nil, generator: nil),
        CatalogCategory(id: "fireplace", title: "Cozy Fireplace", symbol: "flame", colors: ["#1A0800", "#FF8F00"],
                        pexels: "fireplace", pixabay: "fireplace", nasa: nil, generator: nil),
        CatalogCategory(id: "snow", title: "Snowfall", symbol: "snowflake", colors: ["#0B1320", "#90CAF9"],
                        pexels: "snow falling", pixabay: "snowfall", nasa: nil, generator: nil),
        CatalogCategory(id: "storm", title: "Lightning Storms", symbol: "cloud.bolt.fill", colors: ["#07070F", "#5C6BC0"],
                        pexels: "lightning storm", pixabay: "thunderstorm lightning", nasa: nil, generator: nil),
        CatalogCategory(id: "underwater", title: "Underwater", symbol: "fish.fill", colors: ["#011526", "#0288D1"],
                        pexels: "underwater", pixabay: "underwater", nasa: nil, generator: nil),
        CatalogCategory(id: "abstract", title: "Abstract Motion", symbol: "circle.hexagongrid.fill", colors: ["#0A0A14", "#00B8D4"],
                        pexels: "abstract background loop", pixabay: "abstract loop", nasa: nil, generator: nil),
    ]
}

/// The catalog can be updated without shipping a new build: the app fetches `Catalog/catalog.json`
/// from the repository and falls back to the built-in list.
struct RemoteCatalog: Codable, Sendable {
    let version: Int
    let categories: [CatalogCategory]
}

enum CatalogLoader {
    static func cached() -> [CatalogCategory]? {
        guard let data = try? Data(contentsOf: AppPaths.catalogCacheFile),
              let catalog = try? JSONDecoder().decode(RemoteCatalog.self, from: data),
              !catalog.categories.isEmpty else { return nil }
        return catalog.categories
    }

    static func fetch(from urlString: String) async -> [CatalogCategory]? {
        guard let url = URL(string: urlString), url.scheme == "https" else { return nil }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await HTTPClient.session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let catalog = try JSONDecoder().decode(RemoteCatalog.self, from: data)
            guard !catalog.categories.isEmpty else { return nil }
            try? data.write(to: AppPaths.catalogCacheFile, options: .atomic)
            return catalog.categories
        } catch {
            return nil
        }
    }
}
