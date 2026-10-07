import Foundation

/// The user's wallpaper collection. Video files live in `AppPaths.videos`; metadata in `library.json`.
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var wallpapers: [Wallpaper] = []

    private init() {}

    func load() {
        wallpapers = Self.readFromDisk()
            .filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
            .sorted { $0.dateAdded > $1.dateAdded }
    }

    /// Thread-safe read used by App Intents, which may run before the UI is loaded.
    nonisolated static func readFromDisk() -> [Wallpaper] {
        guard let data = try? Data(contentsOf: AppPaths.libraryFile) else { return [] }
        return (try? JSONDecoder.iso8601.decode([Wallpaper].self, from: data)) ?? []
    }

    private func save() {
        do {
            let data = try JSONEncoder.pretty.encode(wallpapers)
            try data.write(to: AppPaths.libraryFile, options: .atomic)
        } catch {
            NSLog("VideoWallpaper: failed to save library: \(error)")
        }
    }

    // MARK: - Queries

    var favorites: [Wallpaper] { wallpapers.filter(\.isFavorite) }

    func wallpaper(id: UUID?) -> Wallpaper? {
        guard let id else { return nil }
        return wallpapers.first { $0.id == id }
    }

    func wallpaper(remoteID: String) -> Wallpaper? {
        wallpapers.first { $0.remoteID == remoteID }
    }

    func wallpaper(named name: String) -> Wallpaper? {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        return wallpapers.first { $0.name.compare(needle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            ?? wallpapers.first { $0.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    // MARK: - Mutations

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = wallpapers.firstIndex(where: { $0.id == id }) else { return }
        wallpapers[index].name = trimmed
        save()
    }

    func toggleFavorite(_ id: UUID) {
        guard let index = wallpapers.firstIndex(where: { $0.id == id }) else { return }
        wallpapers[index].isFavorite.toggle()
        save()
    }

    func remove(ids: Set<UUID>) {
        let removed = wallpapers.filter { ids.contains($0.id) }
        for wallpaper in removed {
            try? FileManager.default.removeItem(at: wallpaper.fileURL)
            try? FileManager.default.removeItem(at: wallpaper.thumbnailURL)
            try? FileManager.default.removeItem(at: wallpaper.stillURL)
            ThumbnailCache.shared.invalidate(wallpaper.thumbnailURL)
        }
        wallpapers.removeAll { ids.contains($0.id) }
        save()
    }

    /// Brings a video file into the library: moves (downloads, renders) or copies (imports) it,
    /// reads its metadata and creates a thumbnail.
    func addVideo(
        from source: URL,
        move: Bool,
        name: String,
        origin: Wallpaper.Origin,
        provider: String? = nil,
        author: String? = nil,
        pageURL: URL? = nil,
        remoteID: String? = nil
    ) async throws -> Wallpaper {
        let id = UUID()
        let sourceExtension = source.pathExtension.lowercased()
        let fileExtension = VideoInspector.supportedExtensions.contains(sourceExtension) ? sourceExtension : "mp4"
        let fileName = "\(id.uuidString).\(fileExtension)"
        let destination = AppPaths.videos.appendingPathComponent(fileName)

        // Copies of large files from external drives can take a while; keep them off the main thread.
        try await Task.detached(priority: .userInitiated) {
            if move {
                try FileManager.default.moveItem(at: source, to: destination)
            } else {
                try FileManager.default.copyItem(at: source, to: destination)
            }
        }.value

        do {
            let info = try await VideoInspector.inspect(destination)
            let wallpaper = Wallpaper(
                id: id,
                name: name,
                fileName: fileName,
                origin: origin,
                provider: provider,
                author: author,
                pageURL: pageURL,
                remoteID: remoteID,
                pixelWidth: info.width,
                pixelHeight: info.height,
                duration: info.duration,
                fileSize: info.fileSize
            )
            do {
                try await Thumbnailer.makeThumbnail(for: destination, to: wallpaper.thumbnailURL)
            } catch {
                NSLog("VideoWallpaper: thumbnail failed for \(name): \(error)")
            }
            wallpapers.insert(wallpaper, at: 0)
            save()
            return wallpaper
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// Imports the user's own video files (copied into the library).
    func importFiles(_ urls: [URL]) async -> (imported: [Wallpaper], failures: [String]) {
        var imported: [Wallpaper] = []
        var failures: [String] = []
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            let name = Self.prettyName(from: url)
            guard VideoInspector.supportedExtensions.contains(url.pathExtension.lowercased()) else {
                failures.append("\(url.lastPathComponent): unsupported format (use MP4, MOV or M4V)")
                continue
            }
            do {
                let wallpaper = try await addVideo(from: url, move: false, name: name, origin: .imported)
                imported.append(wallpaper)
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (imported, failures)
    }

    static func prettyName(from url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return "Untitled Video" }
        return base.prefix(1).uppercased() + base.dropFirst()
    }
}
