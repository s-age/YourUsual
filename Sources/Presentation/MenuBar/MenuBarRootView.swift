import SwiftUI

struct MenuBarRootView: View {
    @Bindable var viewModel: MenuItemsViewModel
    /// Shared with every pad window + Settings; backs the "Pads" section's list of
    /// openable pads. Same instance the panels bind, so the list stays live as
    /// Settings mutates pads.
    @Bindable var padViewModel: PadViewModel
    let activate: @MainActor () -> Void
    /// Opens (toggles) the pad with the given layout id in its own non-activating
    /// panel. No `activate()` is involved — summoning a pad must not steal focus.
    let openPad: @MainActor (UUID) -> Void
    /// Points the Settings window at the Current Directory pane before it is opened, so the
    /// current-directory row lands there instead of the last-used selection.
    let revealCurrentDirectorySettings: @MainActor () -> Void
    let quit: @MainActor () -> Void

    @Environment(\.openWindow) private var openWindow

    init(
        viewModel: MenuItemsViewModel,
        padViewModel: PadViewModel,
        activate: @escaping @MainActor () -> Void,
        openPad: @escaping @MainActor (UUID) -> Void,
        revealCurrentDirectorySettings: @escaping @MainActor () -> Void,
        quit: @escaping @MainActor () -> Void
    ) {
        self.viewModel = viewModel
        self.padViewModel = padViewModel
        self.activate = activate
        self.openPad = openPad
        self.revealCurrentDirectorySettings = revealCurrentDirectorySettings
        self.quit = quit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionRow(title: "Settings", systemImage: "gearshape") {
                // An `.accessory` (LSUIElement) app does not auto-activate, so a
                // window opened from the menu bar lands behind the frontmost app.
                // Activate first so the settings window comes to the front.
                activate()
                openWindow(id: "settings")
            }

            CurrentDirectoryMenuRow(path: viewModel.currentDirectory?.path) {
                revealCurrentDirectorySettings()
                activate()
                openWindow(id: "settings")
            }

            Divider().padding(.vertical, 4)

            padsSection

            Divider().padding(.vertical, 4)

            categoryList

            Divider().padding(.vertical, 4)

            launchAtLoginRow

            Divider().padding(.vertical, 4)

            quitRow
        }
        .padding(.vertical, 6)
        .frame(width: 260)
        .task { await viewModel.load() }
        .task { await padViewModel.load() }
        // Surface a failed open/load instead of swallowing it — a click on a
        // missing path/app or a read failure shows here rather than failing mute.
        .actionErrorAlert($viewModel.actionError)
    }

    // MARK: - Subviews

    /// Lists every pad, each row summoning that pad's own non-activating panel by id.
    /// No `activate()` — opening a pad must not steal focus (mirrors the former single
    /// "Open Pad" row). When no pad exists yet, a single row points to Settings → Pads.
    @ViewBuilder
    private var padsSection: some View {
        let pads = padViewModel.response.layouts.sorted { $0.sortIndex < $1.sortIndex }
        sectionHeader("Pads")
        if pads.isEmpty {
            // Creating a pad happens in Settings; bring it to the front first
            // (an `.accessory` app does not auto-activate).
            actionRow(title: "Add a pad in Settings…", systemImage: "plus") {
                activate()
                openWindow(id: "settings")
            }
        } else {
            ForEach(pads, id: \.id) { pad in
                // Indented to align with the entry rows under each category section
                // (`rowLabel`'s leading 24), so a pad reads as an item of its "Pads"
                // section rather than a top-level action like Settings.
                actionRow(title: pad.name, systemImage: "rectangle.grid.2x2", indented: true) {
                    openPad(pad.id)
                }
            }
        }
    }

    /// One section per non-empty category. When nothing is registered yet, show
    /// the first category's header (Default) with an empty-state line.
    @ViewBuilder
    private var categoryList: some View {
        let sections = viewModel.sections
        let nonEmpty = sections.filter { !$0.items.isEmpty }
        if nonEmpty.isEmpty {
            sectionHeader(sections.first?.name ?? "Default")
            Text("No items registered")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
        } else {
            ForEach(nonEmpty) { section in
                sectionHeader(section.name)
                ForEach(section.items) { item in
                    entryRow(item)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
    }

    @ViewBuilder
    private func entryRow(_ item: SavedEntryResponse) -> some View {
        if item.execution == .runAndStream {
            backgroundCommandRow(item)
        } else {
            Button {
                Task { await viewModel.open(item) }
            } label: {
                rowLabel(item, running: false)
            }
            .buttonStyle(.plain)
        }
    }

    /// Background command: runs on click. The result window opens lazily — only once the
    /// run produces output or finishes with a non-zero exit (the ViewModel bumps
    /// `presentResultTick`, observed by the always-mounted status-item label so the open
    /// survives the menu closing). A run that finishes exit 0 with no output never opens a
    /// window; its completion notification is the only surface. Disabled with a spinner
    /// while running so a row can't be double-launched.
    @ViewBuilder
    private func backgroundCommandRow(_ item: SavedEntryResponse) -> some View {
        let running = viewModel.isRunning(item.id)
        Button {
            viewModel.run(item)
        } label: {
            rowLabel(item, running: running)
        }
        .buttonStyle(.plain)
        .disabled(running)
    }

    /// Shared icon-column width for menu rows ≈ the SF Symbol's optical box at the menu
    /// font, so bitmap app icons match the symbols and every text left-edge aligns.
    private let iconColumnWidth: CGFloat = 17

    @ViewBuilder
    private func rowLabel(_ item: SavedEntryResponse, running: Bool) -> some View {
        let appIconURL = item.kind.appBundleIdentifier
            .flatMap { viewModel.appIconURL(forBundleIdentifier: $0) }
        HStack(spacing: 6) {
            if running {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: iconColumnWidth)
            } else if let appIconURL {
                // Sized to the SF Symbol's optical box so app-icon rows and symbol rows
                // read at the same size and keep their text left-edges aligned.
                AsyncImage(url: appIconURL) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Image(systemName: item.kind.iconSystemName)
                        .foregroundStyle(.secondary)
                }
                .frame(width: iconColumnWidth, height: iconColumnWidth)
            } else {
                Image(systemName: item.kind.iconSystemName)
                    .frame(width: iconColumnWidth)
                    .foregroundStyle(item.kind.isTerminalCommand
                        ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.tail)
            if item.isRecovered {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("This item couldn’t be loaded and is shown as a placeholder.")
            }
            Spacer()
        }
        .padding(.leading, 24)
        .padding(.trailing, 12)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

}

// Leaf presentational rows, kept in an extension so the primary struct body stays
// within `type_body_length` (the linter counts only the primary declaration).
private extension MenuBarRootView {
    @ViewBuilder
    var launchAtLoginRow: some View {
        HStack {
            Text("Launch at Login")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { viewModel.launchAtLogin },
                set: { viewModel.setLaunchAtLogin($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    var quitRow: some View {
        HStack(spacing: 6) {
            Spacer()
            Button {
                quit()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                    Text("Quit")
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    func actionRow(
        title: String,
        systemImage: String,
        indented: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).frame(width: 14)
                Text(title)
                Spacer()
            }
            // Indented rows align with the entry rows under a section (`rowLabel`'s
            // leading 24); top-level actions keep the 12 used by the section headers.
            .padding(EdgeInsets(top: 4, leading: indented ? 24 : 12, bottom: 4, trailing: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Shows the global current directory (the value `<WORKING_DIRECTORY>` commands and
/// `$YOUR_USUAL_CURRENT_DIRECTORY` resolve to), abbreviated with `~`. Click opens Settings,
/// where it is set. Held in memory only, so it resets to home on relaunch; also changeable
/// from a terminal via `your-usual cd <path>`.
private struct CurrentDirectoryMenuRow: View {
    let path: String?
    let onOpen: () -> Void

    var body: some View {
        let display = path.map { ($0 as NSString).abbreviatingWithTildeInPath }
        Button(action: onOpen) {
            HStack(spacing: 6) {
                Image(systemName: "folder").frame(width: 14)
                Text(display ?? "—")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Current directory — click to change in Settings")
    }
}
