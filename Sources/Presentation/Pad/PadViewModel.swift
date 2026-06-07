import SwiftUI
import Observation

@Observable
@MainActor
final class PadViewModel {
    // MARK: - Published state
    private(set) var response: PadLayoutsResponse = PadLayoutsResponse(layouts: [], cells: [])
    var actionError: String?

    // MARK: - Dependencies
    private let readPadLayouts: ReadPadLayoutsUseCaseProtocol
    private let registerPadLayout: RegisterPadLayoutUseCaseProtocol
    private let editPadLayout: EditPadLayoutUseCaseProtocol
    private let deletePadLayout: DeletePadLayoutUseCaseProtocol
    private let reorderPadLayouts: ReorderPadLayoutsUseCaseProtocol
    private let savePadCell: SavePadCellUseCaseProtocol
    private let deletePadCell: DeletePadCellUseCaseProtocol
    private let probeIconImage: ProbeIconImageUseCaseProtocol
    private let openEntry: OpenEntryUseCaseProtocol
    private let runSlider: RunSliderUseCaseProtocol
    private let setSliderValue: SetSliderValueUseCaseProtocol
    private let menu: MenuItemsViewModel      // reused for runAndStream activation + result window
    /// Shared with the menu and settings so an app icon resolved on any surface is reused —
    /// a "open with app" cell shows the real application icon, matching those surfaces.
    private let appIcons: AppIconCache

    /// Coalesces a slider's rapid drag changes to one throttled run, and guarantees the
    /// final value runs on release. Shared across all slider cells (keyed per entry id).
    private let sliderThrottler: SliderThrottler

    /// Invoked after a pad layout is successfully deleted, so the App layer can tear
    /// down that pad's open launcher panel (close it + drop it from the panel registry),
    /// leaving no orphaned window for a pad that no longer exists. Set by `AppBootstrap`;
    /// the Presentation/UseCase/Domain layers stay AppKit-free and know nothing about
    /// `NSPanel`. `@ObservationIgnored` — it's wired once at startup, not observed state.
    @ObservationIgnored
    var onLayoutDeleted: (@MainActor (UUID) -> Void)?

    init(
        readPadLayouts: ReadPadLayoutsUseCaseProtocol,
        registerPadLayout: RegisterPadLayoutUseCaseProtocol,
        editPadLayout: EditPadLayoutUseCaseProtocol,
        deletePadLayout: DeletePadLayoutUseCaseProtocol,
        reorderPadLayouts: ReorderPadLayoutsUseCaseProtocol,
        savePadCell: SavePadCellUseCaseProtocol,
        deletePadCell: DeletePadCellUseCaseProtocol,
        probeIconImage: ProbeIconImageUseCaseProtocol,
        openEntry: OpenEntryUseCaseProtocol,
        runSlider: RunSliderUseCaseProtocol,
        setSliderValue: SetSliderValueUseCaseProtocol,
        menu: MenuItemsViewModel,
        appIcons: AppIconCache,
        sliderThrottler: SliderThrottler
    ) {
        self.readPadLayouts    = readPadLayouts
        self.registerPadLayout = registerPadLayout
        self.editPadLayout     = editPadLayout
        self.deletePadLayout   = deletePadLayout
        self.reorderPadLayouts = reorderPadLayouts
        self.savePadCell       = savePadCell
        self.deletePadCell     = deletePadCell
        self.probeIconImage    = probeIconImage
        self.openEntry         = openEntry
        self.runSlider         = runSlider
        self.setSliderValue    = setSliderValue
        self.menu              = menu
        self.appIcons          = appIcons
        self.sliderThrottler   = sliderThrottler
    }

    // MARK: - Computed helpers

    /// Live entry catalog for the cell editor's picker — a pass-through to the shared
    /// menu VM's `items` (itself the shared `RegistryViewModel.items`). Read live (not
    /// a snapshot) so entries registered after the pad opened appear in the picker;
    /// `@Observable` propagates the change through to the (NSPanel-hosted) view.
    var entries: [SavedEntryResponse] { menu.items }

    func cells(forLayout id: UUID) -> [PadCellResponse] {
        response.cells.filter { $0.layoutID == id }
    }

    /// Whether a cell's entry runs-and-streams (so the View must open the result window).
    func isStreaming(_ cell: PadCellResponse) -> Bool {
        cell.entry?.execution == .runAndStream
    }

    // MARK: - Intent

    func load() async {
        do {
            response = try await readPadLayouts.execute(ReadPadLayoutsRequest())
        } catch is CancellationError {
            return
        } catch {
            actionError = error.localizedDescription
            return
        }
        // Resolve app icons for "open with app" cells so a tile shows the real application
        // icon instead of the generic folder symbol — matching the menu and settings. Shared
        // cache, so any icon already resolved by those surfaces is reused (no re-fetch).
        await appIcons.resolve(for: response.cells.compactMap(\.entry))
    }

    /// File URL of the cached icon for the app a browse cell opens with, if resolved; nil
    /// falls back to the SF Symbol. Forwards to the shared `AppIconCache` (read live in a
    /// cell's `body`, so it re-renders once `load()` populates the cache).
    func appIconURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        appIcons.url(forBundleIdentifier: bundleIdentifier)
    }

    // MARK: - Layout management (Settings "Pads" tab)
    //
    // These operate on an explicit `id` (the Settings selection). Each launcher panel
    // is pinned to its own `layoutID`, so adding/editing/reordering a pad from Settings
    // never shifts what an open panel shows.

    private func layoutIndex(_ id: UUID?) -> Int? {
        guard let id else { return nil }
        return response.layouts.firstIndex { $0.id == id }
    }

    /// Whether `id` can move by `offset` (±1) without leaving the list bounds.
    func canMoveLayout(id: UUID?, by offset: Int) -> Bool {
        guard let index = layoutIndex(id) else { return false }
        return response.layouts.indices.contains(index + offset)
    }

    /// Registers a new pad and returns its id on success (nil on validation failure, so
    /// the caller keeps the typed input). Does **not** change any selection — the caller
    /// decides whether to select it (Settings does; the panel is untouched).
    @discardableResult
    func registerLayout(name: String, columns: Int, rows: Int) async -> UUID? {
        do {
            let created = try await registerPadLayout.execute(
                RegisterPadLayoutRequest(name: name, columns: columns, rows: rows)
            )
            await load()
            return created.id
        } catch {
            actionError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func editLayout(id: UUID, name: String, columns: Int, rows: Int) async -> Bool {
        do {
            _ = try await editPadLayout.execute(
                EditPadLayoutRequest(id: id, name: name, columns: columns, rows: rows)
            )
            await load()
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    func deleteLayout(id: UUID) async {
        do {
            try await deletePadLayout.execute(DeletePadLayoutRequest(id: id))
            onLayoutDeleted?(id)   // tear down the deleted pad's open panel, if any
            await load()
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// Moves the pad `id` one step up (-1) or down (+1), mirroring the category sidebar's
    /// reorder buttons. No-op when the move would leave the bounds.
    func moveLayout(id: UUID?, by offset: Int) async {
        guard let index = layoutIndex(id) else { return }
        let target = index + offset
        guard response.layouts.indices.contains(target) else { return }
        var ordered = response.layouts.map(\.id)
        ordered.swapAt(index, target)
        do {
            try await reorderPadLayouts.execute(ReorderPadLayoutsRequest(orderedIDs: ordered))
            await load()
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// Reloads through `ReadPadLayoutsUseCase` after a mutation so cells carry
    /// resolved `entry` snapshots (the mutation use cases return `Void`).
    /// Returns `true` on success so the editor sheet dismisses only when the save
    /// actually committed — an overlap/bounds rejection keeps the sheet (and its
    /// in-progress input) open while the error surfaces via `actionError`.
    @discardableResult
    func saveCell(_ request: SavePadCellRequest) async -> Bool {
        do {
            try await savePadCell.execute(request)
            await load()
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    func deleteCell(layoutID: UUID, column: Int, row: Int, iconImageName: String?) async {
        do {
            try await deletePadCell.execute(
                DeletePadCellRequest(layoutID: layoutID, column: column, row: row,
                                     iconImageName: iconImageName)
            )
            await load()
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// Probes a source image's pixel size for the crop editor. Returns nil on
    /// cancellation (no surfacing) or surfaces other failures via `actionError`.
    func probeIcon(path: String) async -> IconImageSizeResponse? {
        do {
            return try await probeIconImage.execute(ProbeIconImageRequest(sourcePath: path))
        } catch is CancellationError {
            return nil
        } catch {
            actionError = error.localizedDescription
            return nil
        }
    }

    /// Routes activation by the entry's execution style, mirroring the menu:
    /// `.open` runs the open use case (errors surface here); `.runAndStream`
    /// delegates to the shared menu VM, which streams into the result window.
    /// The result window itself is opened by the View (activate-first).
    func activateCell(_ cell: PadCellResponse) async {
        guard let entry = cell.entry else { return }
        switch entry.execution {
        case .open:
            do {
                try await openEntry.execute(OpenEntryRequest(entry: entry))
            } catch {
                actionError = error.localizedDescription
            }
        case .runAndStream:
            menu.run(entry)   // fire-and-forget; the View opens the result window
        case .adjust:
            break             // sliders are driven by the Slider UI's drag, not a tap
        }
    }

    // MARK: - Slider intents
    //
    // A slider cell drives two intents: `adjustSlider` while dragging (throttled, no
    // notification/history — `RunSliderUseCase` structurally cannot emit them) and
    // `commitSlider` on release (runs the final value on the throttle chain, and persists the
    // new position *independently* of that run — see `commitSlider`).
    // The throttled run's failure is swallowed (the next drag supersedes it). The commit's
    // persistence is also kept quiet in the UI (a self-correcting position save shouldn't pop
    // an alert), but it is no longer *silently lost*: `SetSliderValueUseCase` logs the failure
    // via diagnostics before rethrowing, so the `try?` here only suppresses the UI surface.

    /// Runs the slider's command for the in-flight drag value, throttled per entry so a fast
    /// drag issues at most one run per window.
    func adjustSlider(cell: PadCellResponse, value: Double) {
        guard let entry = cell.entry else { return }
        sliderThrottler.tick(entry.id) { [runSlider] in
            try? await runSlider.execute(RunSliderRequest(entry: entry, value: value))
        }
    }

    /// On drag release: flushes the final value (so the tail isn't dropped) and persists the
    /// new slider position once.
    func commitSlider(cell: PadCellResponse, value: Double) {
        guard let entry = cell.entry else { return }
        // Persist the final position independently of the command run — NOT inside the
        // throttle's bounded chain. Saving the position is a fast local write that must always
        // land; the command run can overrun and be abandoned by `runBounded` (the
        // grandchild-holds-the-pipe case it guards against), which would otherwise drop the
        // save and revert the slider to its old value on next open. Keeping them on one timeout
        // budget coupled persistence to the external command's lifetime, which is wrong.
        Task { [setSliderValue] in
            try? await setSliderValue.execute(SetSliderValueRequest(entryID: entry.id, value: value))
        }
        // The command run goes on the bounded serial chain (last-wins ordering; can't wedge).
        sliderThrottler.commit(entry.id) { [runSlider] in
            try? await runSlider.execute(RunSliderRequest(entry: entry, value: value))
        }
    }
}
