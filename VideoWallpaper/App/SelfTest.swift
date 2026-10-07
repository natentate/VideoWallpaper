import AppKit
import AVFoundation

/// End-to-end smoke test run by CI: `VideoWallpaper --self-test`.
/// Exercises the generators, library, desktop playback engine, Focus switching, URL scheme,
/// provider parsing and (network permitting) a live NASA search + download, then exits 0/1.
@MainActor
enum SelfTest {
    static var isRequested: Bool { CommandLine.arguments.contains("--self-test") }

    private static var failures: [String] = []

    private static func check(_ condition: Bool, _ message: String) {
        print("\(condition ? "PASS" : "FAIL") · \(message)")
        if !condition { failures.append(message) }
    }

    private static func note(_ message: String) {
        print("INFO · \(message)")
    }

    static func run() {
        setvbuf(stdout, nil, _IOLBF, 0)
        Task { @MainActor in
            await execute()
            print(failures.isEmpty ? "SELF-TEST PASSED" : "SELF-TEST FAILED (\(failures.count)): \(failures.joined(separator: " | "))")
            fflush(stdout)
            exit(failures.isEmpty ? 0 : 1)
        }
    }

    private static func execute() async {
        let model = AppModel.shared
        let library = LibraryStore.shared
        model.start()
        note("data directory: \(AppPaths.root.path)")
        check(!NSScreen.screens.isEmpty, "found \(NSScreen.screens.count) screen(s)")

        checkSeamlessLoops()

        // Generators → library
        let matrix = await generate(GeneratorRequest(kind: .matrix, width: 640, height: 360, seconds: 3, seed: 42, name: "Self-test Matrix"))
        let stars = await generate(GeneratorRequest(
            kind: .starfield, width: 640, height: 360, seconds: 3, seed: 7,
            starfield: StarfieldSettings(style: .warp, density: 0.8, nebula: true, tint: .blue),
            name: "Self-test Stars"
        ))
        guard let matrix, let stars else {
            check(false, "generators produced videos")
            return
        }
        for wallpaper in [matrix, stars] {
            let info = try? await VideoInspector.inspect(wallpaper.fileURL)
            let width: Int = info?.width ?? 0
            let height: Int = info?.height ?? 0
            let duration: Double = info?.duration ?? 0
            check(width == 640 && height == 360, "\(wallpaper.name) is 640×360 (got \(width)×\(height))")
            check(abs(duration - 3.0) < 0.25, "\(wallpaper.name) lasts 3s (got \(duration))")
            check(FileManager.default.fileExists(atPath: wallpaper.thumbnailURL.path), "\(wallpaper.name) has a thumbnail")
        }

        // Desktop playback
        model.setWallpaper(matrix.id)
        try? await Task.sleep(for: .seconds(3))
        let status = model.engineStatus
        check(!status.isEmpty, "desktop windows created (\(status.count))")
        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
        for screen in status {
            note("display \(screen.displayID): onScreen=\(screen.isWindowOnScreen) level=\(screen.windowLevel) visible=\(screen.isVisible) playing=\(screen.playback?.isPlaying ?? false) ready=\(screen.playback?.isReadyForDisplay ?? false) t=\(screen.playback?.currentTime ?? -1) error=\(screen.playback?.error ?? "none")")
            check(screen.isWindowOnScreen, "wallpaper window is on screen")
            check(screen.windowLevel == desktopLevel, "wallpaper window sits at the desktop level")
            check(screen.playback?.isReadyForDisplay == true, "video layer is ready for display")
            check(screen.playback?.error == nil, "player has no error")
        }
        note("status text: \(model.statusText)")
        if !model.isPlaybackBlocked {
            let before = model.engineStatus.compactMap { $0.playback?.currentTime }
            try? await Task.sleep(for: .seconds(1.5))
            let after = model.engineStatus.compactMap { $0.playback?.currentTime }
            check(before != after, "playback time advances (\(before) → \(after))")
            check(model.engineStatus.allSatisfy { $0.playback?.isPlaying == true || !$0.isVisible }, "visible displays are playing")
        } else {
            note("playback blocked on this machine: \(model.statusText)")
        }

        // Manual pause / resume via URL scheme
        model.handle(url: URL(string: "videowallpaper://pause")!)
        try? await Task.sleep(for: .milliseconds(500))
        check(model.state.isPaused && model.engineStatus.allSatisfy { $0.playback?.isPlaying != true }, "pause URL stops playback")
        model.handle(url: URL(string: "videowallpaper://resume")!)
        check(!model.state.isPaused, "resume URL clears pause")

        // Focus switching
        let profileID = model.addFocusProfile(name: "Self Test", symbol: "sparkles")
        model.updateFocusProfile(profileID) { $0.wallpaperID = stars.id }
        model.handle(url: URL(string: "videowallpaper://focus/on?name=Self%20Test")!)
        check(isPlayingEverywhere(stars.id), "Focus on → Focus wallpaper plays")
        check(model.activeFocusProfile?.id == profileID, "Focus profile reported active")
        model.handle(url: URL(string: "videowallpaper://focus/off?name=self%20test")!)
        check(isPlayingEverywhere(matrix.id), "Focus off → regular wallpaper returns")
        model.applyFocusFilter(profileID: profileID, wallpaperID: nil)
        check(isPlayingEverywhere(stars.id), "Focus Filter activation switches wallpaper")
        model.applyFocusFilter(profileID: nil, wallpaperID: nil)
        check(isPlayingEverywhere(matrix.id), "Focus Filter deactivation restores wallpaper")
        model.updateFocusProfile(profileID) { $0.pausesPlayback = true }
        model.activateFocus(profileID)
        check(model.isPlaybackBlocked, "Focus with “pause video” pauses playback")
        model.deactivateFocus(nil)
        check(!model.state.isPaused && model.state.activations.isEmpty, "all Focus wallpapers cleared")

        // URL: set / next
        model.handle(url: URL(string: "videowallpaper://set?name=self-test%20stars")!)
        check(isPlayingEverywhere(stars.id), "set?name= selects a wallpaper by name")
        model.handle(url: URL(string: "videowallpaper://next")!)
        check(!isPlayingEverywhere(stars.id), "next advances to another wallpaper")

        // Import your own video
        let external = FileManager.default.temporaryDirectory.appendingPathComponent("my_clip.mov")
        try? FileManager.default.removeItem(at: external)
        try? FileManager.default.copyItem(at: matrix.fileURL, to: external)
        let result = await library.importFiles([external])
        check(result.imported.count == 1 && result.failures.isEmpty, "imported a user video (\(result.failures))")
        if let imported = result.imported.first {
            check(imported.name == "My clip", "import name is prettified (\(imported.name))")
            model.deleteWallpapers([imported.id])
            check(!FileManager.default.fileExists(atPath: imported.fileURL.path), "deleting removes the library file")
            check(FileManager.default.fileExists(atPath: external.path), "deleting leaves the original file alone")
        }

        // App Intents entity query reads the library from disk
        let entities = (try? await WallpaperEntityQuery().suggestedEntities()) ?? []
        check(entities.count == library.wallpapers.count, "Shortcuts entity query lists \(entities.count) wallpapers")
        let profiles = (try? await FocusProfileEntityQuery().suggestedEntities()) ?? []
        check(profiles.contains { $0.id == profileID }, "Shortcuts Focus profile query includes new profile")

        checkProviderParsing()
        await checkNASA()
    }

    private static func isPlayingEverywhere(_ id: UUID) -> Bool {
        let model = AppModel.shared
        return !model.displays.isEmpty && model.displays.allSatisfy { model.nowPlaying[$0.id] == id }
    }

    private static func generate(_ request: GeneratorRequest) async -> Wallpaper? {
        let service = GeneratorService.shared
        let started = Date()
        service.generate(request, setWhenFinished: false)
        while Date().timeIntervalSince(started) < 180 {
            if let job = service.job {
                switch job.phase {
                case .finished(let id):
                    note("rendered \(request.name) in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
                    service.dismiss()
                    return LibraryStore.shared.wallpaper(id: id)
                case .failed(let message):
                    check(false, "rendering \(request.name) failed: \(message)")
                    service.dismiss()
                    return nil
                case .cancelled:
                    check(false, "rendering \(request.name) was cancelled")
                    service.dismiss()
                    return nil
                case .rendering, .saving:
                    break
                }
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        check(false, "rendering \(request.name) timed out")
        return nil
    }

    /// The last frame of a loop must flow into the first: frame N renders identically to frame 0.
    private static func checkSeamlessLoops() {
        let requests = [
            GeneratorRequest(kind: .matrix, width: 480, height: 270, seconds: 4, seed: 3, name: "loop"),
            GeneratorRequest(kind: .starfield, width: 480, height: 270, seconds: 4, seed: 3, starfield: StarfieldSettings(style: .warp), name: "loop"),
        ]
        for request in requests {
            let first = pixels(VideoEncoder.previewImage(request: request, frame: 0))
            let wrapped = pixels(VideoEncoder.previewImage(request: request, frame: request.totalFrames))
            let later = pixels(VideoEncoder.previewImage(request: request, frame: request.totalFrames / 2))
            check(first != nil && first == wrapped, "\(request.kind.title) loops seamlessly")
            check(first != nil && first != later, "\(request.kind.title) animates between frames")
        }
    }

    private static func pixels(_ image: CGImage?) -> Data? {
        image?.dataProvider?.data as Data?
    }

    private static func checkProviderParsing() {
        let pexels = Data(#"""
        {"page":1,"per_page":1,"total_results":1,"videos":[{"id":3645365,"width":3840,"height":2160,"duration":24,
        "url":"https://www.pexels.com/video/rain-drops-on-a-window-3645365/","image":"https://images.pexels.com/videos/3645365/preview.jpg",
        "user":{"id":1,"name":"Jane Doe","url":"https://www.pexels.com/@jane"},
        "video_files":[
          {"id":1,"quality":"hd","file_type":"video/mp4","width":1920,"height":1080,"fps":25,"link":"https://videos.pexels.com/video-files/3645365/hd.mp4","size":12345678},
          {"id":2,"quality":"uhd","file_type":"video/mp4","width":3840,"height":2160,"fps":25,"link":"https://videos.pexels.com/video-files/3645365/uhd.mp4","size":45678901},
          {"id":3,"quality":"sd","file_type":"video/mp4","width":960,"height":540,"fps":25.0,"link":"https://videos.pexels.com/video-files/3645365/sd.mp4"},
          {"id":4,"quality":"hls","file_type":"video/hls","width":null,"height":null,"fps":null,"link":"https://player.vimeo.com/external/x.m3u8"}],
        "video_pictures":[]}],"next_page":"https://api.pexels.com/v1/videos/search/?page=2&per_page=1&query=rain"}
        """#.utf8)
        do {
            let page = try PexelsProvider.page(from: pexels)
            let video = page.videos.first
            let title: String = video?.title ?? "nil"
            let fileCount: Int = video?.files.count ?? 0
            let bestWidth: Int = video?.bestFile?.width ?? 0
            let cappedWidth: Int = video?.preferredFile(for: .fhd)?.width ?? 0
            let previewWidth: Int = video?.previewFile?.width ?? 0
            check(page.videos.count == 1 && page.hasMore, "Pexels response parses")
            check(title == "Rain drops on a window", "Pexels title derived from page URL (\(title))")
            check(fileCount == 3 && bestWidth == 3840, "Pexels renditions sorted best-first, HLS skipped")
            check(cappedWidth == 1920, "download quality cap picks 1080p")
            check(previewWidth == 960, "preview uses a small rendition")
        } catch {
            check(false, "Pexels parsing threw \(error)")
        }

        let pixabay = Data(#"""
        {"total":1,"totalHits":1,"hits":[{"id":125,"pageURL":"https://pixabay.com/videos/id-125/","type":"film","tags":"rain, window, drops","duration":12,
        "videos":{
          "large":{"url":"https://cdn.pixabay.com/video/2015/08/08/125-135736646_large.mp4","width":3840,"height":2160,"size":6615235,"thumbnail":"https://cdn.pixabay.com/video/2015/08/08/125-135736646_large.jpg"},
          "medium":{"url":"https://cdn.pixabay.com/video/2015/08/08/125-135736646_medium.mp4","width":1920,"height":1080,"size":3562083,"thumbnail":"https://cdn.pixabay.com/video/2015/08/08/125-135736646_medium.jpg"},
          "small":{"url":"","width":0,"height":0,"size":0,"thumbnail":""},
          "tiny":{"url":"https://cdn.pixabay.com/video/2015/08/08/125-135736646_tiny.mp4","width":960,"height":540,"size":1030736,"thumbnail":"https://cdn.pixabay.com/video/2015/08/08/125-135736646_tiny.jpg"}},
        "views":4462,"downloads":1464,"likes":18,"comments":0,"user_id":1281706,"user":"Coverr-Free-Footage","userImageURL":"https://cdn.pixabay.com/user/x.png"}]}
        """#.utf8)
        do {
            let page = try PixabayProvider.page(from: pixabay, page: 1, perPage: 30)
            let video = page.videos.first
            let title: String = video?.title ?? "nil"
            let fileCount: Int = video?.files.count ?? 0
            let bestWidth: Int = video?.bestFile?.width ?? 0
            check(page.videos.count == 1 && !page.hasMore, "Pixabay response parses")
            check(fileCount == 3 && bestWidth == 3840, "Pixabay renditions parsed, empty ones skipped")
            check(title == "Rain, window, drops" && video?.thumbnailURL != nil, "Pixabay title and thumbnail (\(title))")
        } catch {
            check(false, "Pixabay parsing threw \(error)")
        }
    }

    /// Live check against the NASA Image and Video Library (no API key needed).
    private static func checkNASA() async {
        do {
            let page = try await NASAProvider().search(query: "earth from space station", page: 1, only4K: false)
            check(!page.videos.isEmpty, "NASA search returned \(page.videos.count) videos")
            guard let video = page.videos.first else { return }
            let discover = AppModel.shared.discover
            let resolved = try await discover.resolveFiles(for: video)
            note("NASA renditions for \(video.title): \(resolved.files.compactMap(\.label))")
            check(!resolved.files.isEmpty, "NASA manifest lists downloadable files")
            var chosen: RemoteVideoFile?
            for label in ["Mobile", "Preview", "Small", "Medium", "Large", "Original"] where chosen == nil {
                chosen = resolved.files.first { $0.label == label }
            }
            guard let file = chosen ?? resolved.files.last else { return }

            await discover.download(resolved, file: file, setWhenFinished: true)
            let started = Date()
            while Date().timeIntervalSince(started) < 240 {
                if let item = DownloadManager.shared.item(forRemoteID: resolved.id), !item.isActive {
                    if case .failed(let message) = item.phase {
                        check(false, "NASA download failed: \(message)")
                    } else {
                        let wallpaper = LibraryStore.shared.wallpaper(remoteID: resolved.id)
                        check(wallpaper != nil, "NASA download added to library (\(wallpaper?.resolutionLabel ?? "?"))")
                        if let wallpaper {
                            check(isPlayingEverywhere(wallpaper.id), "Download & Set plays the downloaded video")
                        }
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            check(false, "NASA download timed out")
        } catch {
            note("NASA check skipped (network?): \(error.localizedDescription)")
        }
    }
}
