import AppKit
import SwiftUI

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// Loads a thumbnail JPEG from disk without blocking the main thread.
struct LocalThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.35))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "film")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            image = ThumbnailCache.shared.cachedImage(for: url)
            if image == nil {
                image = await ThumbnailCache.shared.image(for: url)
            }
        }
    }
}

/// A 16:9 frame that clips its content with rounded corners.
struct WidescreenFrame<Content: View>: View {
    var cornerRadius: CGFloat = 10
    @ViewBuilder var content: () -> Content

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay { content() }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct Pill: View {
    let text: String
    var systemImage: String?
    var tint: Color = .black.opacity(0.55)

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(tint, in: Capsule())
    }
}

struct ScreenHeader<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            accessory()
        }
    }
}

extension ScreenHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Menu picker for choosing a library wallpaper.
struct WallpaperPicker: View {
    @EnvironmentObject private var library: LibraryStore
    let title: String
    @Binding var selection: UUID?
    var noneLabel = "None"

    var body: some View {
        Picker(title, selection: $selection) {
            Text(noneLabel).tag(UUID?.none)
            if !library.favorites.isEmpty {
                Section("Favorites") {
                    ForEach(library.favorites) { wallpaper in
                        Text(wallpaper.name).tag(UUID?.some(wallpaper.id))
                    }
                }
            }
            Section("Library") {
                ForEach(library.wallpapers.filter { !$0.isFavorite }) { wallpaper in
                    Text(wallpaper.name).tag(UUID?.some(wallpaper.id))
                }
            }
        }
        .pickerStyle(.menu)
    }
}

/// Small rounded card background used across screens.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}

extension View {
    func card() -> some View {
        modifier(CardBackground())
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let red, green, blue: Double
        if cleaned.count == 6, let value = UInt64(cleaned, radix: 16) {
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
        } else {
            red = 0.2
            green = 0.2
            blue = 0.25
        }
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? Color.orange : Color.green)
            Text(toast.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
    }
}
