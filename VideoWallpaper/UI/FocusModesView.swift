import SwiftUI

struct FocusModesView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: LibraryStore
    @State private var customName = ""
    @State private var isAddingCustom = false

    private var unusedPresets: [FocusProfile.Preset] {
        let existing = Set(model.state.focusProfiles.map { $0.name.lowercased() })
        return FocusProfile.presets.filter { !existing.contains($0.name.lowercased()) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(
                    title: "Focus Modes",
                    subtitle: "Give each macOS Focus its own wallpaper. When the Focus turns on, its wallpaper takes over; when it ends, your regular wallpaper returns."
                ) {
                    Menu {
                        ForEach(unusedPresets, id: \.name) { preset in
                            Button {
                                model.addFocusProfile(name: preset.name, symbol: preset.symbol)
                            } label: {
                                Label(preset.name, systemImage: preset.symbol)
                            }
                        }
                        Divider()
                        Button("Custom Focus…") {
                            customName = ""
                            isAddingCustom = true
                        }
                    } label: {
                        Label("Add Focus", systemImage: "plus")
                    }
                    .fixedSize()
                    .controlSize(.large)
                }

                regularWallpaperRow

                ForEach(model.state.focusProfiles) { profile in
                    FocusProfileRow(profile: profile)
                }

                SetupGuide()
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .alert("Add Custom Focus", isPresented: $isAddingCustom) {
            TextField("Name exactly as in System Settings", text: $customName)
            Button("Add") {
                let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    model.addFocusProfile(name: name, symbol: "sparkles")
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var regularWallpaperRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "sun.max.fill")
                .font(.title2)
                .foregroundStyle(.yellow)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("No Focus").font(.headline)
                Text("Your regular wallpaper").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            WallpaperPicker(
                title: "Wallpaper",
                selection: Binding(
                    get: { model.state.defaultWallpaperID },
                    set: { newValue in
                        if let newValue {
                            model.setWallpaper(newValue)
                        } else {
                            model.clearWallpaper()
                        }
                    }
                ),
                noneLabel: "None (system wallpaper)"
            )
            .labelsHidden()
            .frame(width: 260)
        }
        .card()
    }
}

private struct FocusProfileRow: View {
    let profile: FocusProfile

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: LibraryStore
    @State private var showPerDisplay = false
    @State private var confirmDelete = false

    private var isActive: Bool { model.isFocusActive(profile.id) }

    private var assigned: Wallpaper? { library.wallpaper(id: profile.wallpaperID) }

    private func binding<Value>(_ keyPath: WritableKeyPath<FocusProfile, Value>) -> Binding<Value> {
        Binding(
            get: { (model.focusProfile(id: profile.id) ?? profile)[keyPath: keyPath] },
            set: { newValue in model.updateFocusProfile(profile.id) { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func displayBinding(_ displayID: String) -> Binding<UUID?> {
        Binding(
            get: { model.focusProfile(id: profile.id)?.perDisplay[displayID] },
            set: { newValue in
                model.updateFocusProfile(profile.id) { profile in
                    profile.perDisplay[displayID] = newValue
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: profile.symbol)
                    .font(.title2)
                    .foregroundStyle(isActive ? Color.purple : Color.secondary)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 3) {
                    TextField("Focus name", text: binding(\.name))
                        .textFieldStyle(.plain)
                        .font(.headline)
                    HStack(spacing: 6) {
                        if isActive {
                            Pill(text: "Active", systemImage: "moon.fill", tint: .purple)
                        }
                        Text(assigned.map { "Shows “\($0.name)”" } ?? (profile.hasAssignment ? "Per-display wallpapers" : "Not set — keeps your regular wallpaper"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let assigned {
                    WidescreenFrame(cornerRadius: 6) {
                        LocalThumbnail(url: assigned.thumbnailURL)
                    }
                    .frame(width: 96)
                }

                WallpaperPicker(title: "Wallpaper", selection: binding(\.wallpaperID), noneLabel: "Keep regular wallpaper")
                    .labelsHidden()
                    .frame(width: 230)

                Button(isActive ? "Turn Off" : "Try It") {
                    if isActive {
                        model.deactivateFocus(profile.id)
                    } else {
                        model.activateFocus(profile.id)
                    }
                }
                .help("Preview this Focus wallpaper now. It turns on automatically once you connect the Focus below.")

                Menu {
                    Button("Copy “Turn On” URL") { copy(url(on: true)) }
                    Button("Copy “Turn Off” URL") { copy(url(on: false)) }
                    Divider()
                    Button("Delete", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            HStack(spacing: 18) {
                Toggle("Pause video during this Focus", isOn: binding(\.pausesPlayback))
                if model.displays.count > 1 {
                    Toggle("Different wallpaper per display", isOn: $showPerDisplay)
                }
            }
            .font(.callout)
            .padding(.leading, 48)

            if showPerDisplay || (!profile.perDisplay.isEmpty && model.displays.count > 1) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.displays) { display in
                        HStack {
                            Image(systemName: "display")
                            Text(display.name)
                            Spacer()
                            WallpaperPicker(title: display.name, selection: displayBinding(display.id), noneLabel: "Same as above")
                                .labelsHidden()
                                .frame(width: 230)
                        }
                    }
                }
                .padding(.leading, 48)
            }
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isActive ? Color.purple.opacity(0.7) : Color.clear, lineWidth: 2)
        )
        .confirmationDialog("Delete the “\(profile.name)” Focus wallpaper?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { model.removeFocusProfile(profile.id) }
        }
    }

    private func url(on: Bool) -> String {
        let name = profile.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? profile.name
        return "videowallpaper://focus/\(on ? "on" : "off")?name=\(name)"
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        model.showToast("Copied \(string)")
    }
}

/// Explains the three ways to connect a macOS Focus to VideoWallpaper.
private struct SetupGuide: View {
    @State private var method: Method = .shortcuts

    enum Method: String, CaseIterable, Identifiable {
        case shortcuts = "Shortcuts Automation"
        case filter = "Focus Filter"
        case url = "URL / Other Apps"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect your Focus modes").font(.title3.weight(.semibold))
            Text("macOS doesn't let apps read the current Focus directly, so you link each Focus once. Pick a method:")
                .foregroundStyle(.secondary)

            Picker("Method", selection: $method) {
                ForEach(Method.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch method {
            case .shortcuts:
                steps([
                    "Open the **Shortcuts** app and choose **Automation** in the sidebar (macOS 26 Tahoe or later).",
                    "Click **+**, choose **Focus**, pick your Focus (e.g. *Work*) and tick **When Turning On**. Set it to **Run Immediately**.",
                    "Add the action **Turn On Focus Wallpaper** (from VideoWallpaper) and choose the matching profile.",
                    "Create a second automation for **When Turning Off** with **Turn Off Focus Wallpaper**.",
                ])
                Text("Most reliable option on current macOS. Repeat for each Focus you set up above.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Shortcuts") {
                    if let url = URL(string: "shortcuts://") { NSWorkspace.shared.open(url) }
                }
            case .filter:
                steps([
                    "Open **System Settings › Focus** and click a Focus (e.g. *Work*).",
                    "Scroll to **Focus Filters** and click **Add Filter…**.",
                    "Choose **VideoWallpaper**, then pick the **Focus Profile** (or a specific wallpaper).",
                    "macOS switches the wallpaper when the Focus starts and restores it when the Focus ends.",
                ])
                Text("Built into macOS 13+, no Shortcuts needed. Some macOS releases (e.g. 26.5) have had Focus Filter bugs — if it doesn't trigger, use a Shortcuts automation instead.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Focus Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            case .url:
                steps([
                    "Any tool that can open a URL can drive VideoWallpaper (Shortcuts “Open URL”, Raycast, Keyboard Maestro, `open` in Terminal).",
                    "`videowallpaper://focus/on?name=Work` turns on the Work wallpaper; `videowallpaper://focus/off?name=Work` turns it off.",
                    "Also: `videowallpaper://set?name=Rain`, `videowallpaper://next`, `videowallpaper://pause`, `videowallpaper://resume`.",
                ])
                Text("Use the ••• menu on each Focus row to copy its URLs.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func steps(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .frame(width: 20, height: 20)
                        .background(Color.accentColor.opacity(0.2), in: Circle())
                    Text(LocalizedStringKey(item))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
