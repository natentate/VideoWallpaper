import SwiftUI

struct CreateView: View {
    /// Set by other screens (e.g. Discover categories) to preselect a generator.
    static var pendingKind: GeneratorKind?

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var generator: GeneratorService

    @State private var kind: GeneratorKind = .matrix
    @State private var matrix = MatrixSettings()
    @State private var starfield = StarfieldSettings()
    @State private var resolution: GeneratorResolution = .native
    @State private var matrixSeconds = 15
    @State private var seed = UInt64.random(in: 1...UInt64(UInt32.max))
    @State private var name = ""
    @State private var preview: NSImage?

    private var nativeSize: CGSize {
        let largest = model.displays.max { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }
        return CGSize(width: largest?.pixelWidth ?? 3840, height: largest?.pixelHeight ?? 2160)
    }

    private var defaultName: String {
        switch kind {
        case .matrix: return "Matrix Code · \(matrix.palette.title)"
        case .starfield: return "Starfield · \(starfield.style.title)"
        }
    }

    private func request(width: Int, height: Int) -> GeneratorRequest {
        GeneratorRequest(
            kind: kind,
            width: width,
            height: height,
            fps: 30,
            seconds: kind == .matrix ? matrixSeconds : starfield.style.loopSeconds,
            seed: seed,
            matrix: matrix,
            starfield: starfield,
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? defaultName : name
        )
    }

    private var fullRequest: GeneratorRequest {
        let size = resolution.size(native: nativeSize)
        return request(width: size.width, height: size.height)
    }

    /// Changes whenever a setting that affects the picture changes.
    private var previewKey: String {
        "\(kind.rawValue)|\(matrix)|\(starfield)|\(seed)|\(nativeSize.width)x\(nativeSize.height)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(
                    title: "Create",
                    subtitle: "Render seamless, perfectly looping wallpapers on your Mac — no download, any resolution up to 8K."
                )

                HStack(spacing: 14) {
                    ForEach(GeneratorKind.allCases) { item in
                        kindButton(item)
                    }
                }

                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        WidescreenFrame(cornerRadius: 12) {
                            ZStack {
                                Color.black
                                if let preview {
                                    Image(nsImage: preview)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } else {
                                    ProgressView()
                                }
                            }
                        }
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                        Text("Still preview. The rendered video animates and loops seamlessly.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 360, maxWidth: 620)

                    VStack(alignment: .leading, spacing: 14) {
                        if kind == .matrix {
                            matrixOptions
                        } else {
                            starfieldOptions
                        }
                        Divider()
                        outputOptions
                    }
                    .frame(minWidth: 300, maxWidth: 380)
                }
                .card()

                progressOrActions
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .onAppear {
            if let pending = CreateView.pendingKind {
                kind = pending
                CreateView.pendingKind = nil
            }
        }
        .task(id: previewKey) {
            // Debounce rapid slider changes.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let aspect = Double(nativeSize.width / max(nativeSize.height, 1))
            let height = 540
            let width = Int((Double(height) * aspect / 2).rounded()) * 2
            let image = await GeneratorService.preview(request(width: max(2, width), height: height))
            guard !Task.isCancelled else { return }
            preview = image
        }
    }

    private func kindButton(_ item: GeneratorKind) -> some View {
        Button {
            kind = item
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbol)
                    .font(.title2)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.headline)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: 380, alignment: .leading)
            .background(kind == item ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(kind == item ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: kind == item ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var matrixOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Color", selection: $matrix.palette) {
                ForEach(MatrixPalette.allCases) { palette in
                    Text(palette.title).tag(palette)
                }
            }
            Picker("Speed", selection: $matrix.speed) {
                ForEach(RainSpeed.allCases) { speed in
                    Text(speed.title).tag(speed)
                }
            }
            .pickerStyle(.segmented)
            Picker("Glyph size", selection: $matrix.glyphScale) {
                ForEach(GlyphScale.allCases) { scale in
                    Text(scale.title).tag(scale)
                }
            }
            .pickerStyle(.segmented)
            LabeledContent("Density") {
                Slider(value: $matrix.density, in: 0...1)
            }
            Toggle("Background depth layer", isOn: $matrix.depthLayer)
            Toggle("Mirrored glyphs (film style)", isOn: $matrix.mirroredGlyphs)
            Stepper("Loop length: \(matrixSeconds)s", value: $matrixSeconds, in: 8...40, step: 1)
            Button {
                seed = UInt64.random(in: 1...UInt64(UInt32.max))
            } label: {
                Label("Shuffle Pattern", systemImage: "shuffle")
            }
        }
    }

    private var starfieldOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Motion", selection: $starfield.style) {
                ForEach(StarfieldStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            Picker("Star color", selection: $starfield.tint) {
                ForEach(StarTint.allCases) { tint in
                    Text(tint.title).tag(tint)
                }
            }
            .pickerStyle(.segmented)
            LabeledContent("Density") {
                Slider(value: $starfield.density, in: 0...1)
            }
            Toggle("Nebula clouds", isOn: $starfield.nebula)
            Text("Loop length: \(starfield.style.loopSeconds)s")
                .foregroundStyle(.secondary)
            Button {
                seed = UInt64.random(in: 1...UInt64(UInt32.max))
            } label: {
                Label("Shuffle Pattern", systemImage: "shuffle")
            }
        }
    }

    private var outputOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Resolution", selection: $resolution) {
                ForEach(GeneratorResolution.allCases) { option in
                    let size = option.size(native: nativeSize)
                    Text("\(option.title) (\(size.width)×\(size.height))").tag(option)
                }
            }
            TextField("Name", text: $name, prompt: Text(defaultName))
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var progressOrActions: some View {
        if let job = generator.job {
            HStack(spacing: 14) {
                switch job.phase {
                case .rendering, .saving:
                    ProgressView(value: job.progress) {
                        Text(job.phase == .saving ? "Saving to library…" : "Rendering \(job.request.name)… \(Int(job.progress * 100))%")
                    }
                    Button("Cancel") { generator.cancel() }
                        .disabled(job.phase == .saving)
                case .finished:
                    Label("“\(job.request.name)” was added to your library.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Show Library") {
                        generator.dismiss()
                        model.selectedSection = .library
                    }
                    Button("Done") { generator.dismiss() }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Dismiss") { generator.dismiss() }
                case .cancelled:
                    Label("Cancelled", systemImage: "xmark.circle")
                    Spacer()
                    Button("Dismiss") { generator.dismiss() }
                }
            }
            .card()
        }
        if !generator.isBusy {
            HStack(spacing: 12) {
                Spacer()
                Button("Render & Add to Library") {
                    generator.generate(fullRequest, setWhenFinished: false)
                }
                .controlSize(.large)
                Button {
                    generator.generate(fullRequest, setWhenFinished: true)
                } label: {
                    Label("Render & Set as Wallpaper", systemImage: "wand.and.stars")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
