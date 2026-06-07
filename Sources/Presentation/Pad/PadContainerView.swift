import SwiftUI

/// The Launcher Pad, hosted in a non-activating `NSPanel` (see `PadWindowManager`).
/// Launch-only: it lists a chosen pad's cells and fires them on tap. Pad creation and
/// cell editing live in Settings → "Pads" tab; the panel never mutates.
///
/// Each window is **pinned to a single pad** via `layoutID` — there is one panel per
/// pad (opened by name from the menu bar's "Pads" section), so the in-window layout
/// picker is gone. A pad deleted while its window is open falls back to the empty state.
struct PadContainerView: View {
    @Bindable var viewModel: PadViewModel
    /// The pad this window shows. The shared `PadViewModel` backs every pad window;
    /// this id selects which layout's grid this particular window renders.
    let layoutID: UUID
    /// Invoked after a `.runAndStream` cell is fired, to surface its live output.
    /// Injected (not `@Environment(\.openWindow)`) so this view is scene-independent
    /// and can be hosted inside an AppKit non-activating `NSPanel` (which has no
    /// SwiftUI `openWindow` action). In the panel host this is a no-op — the run
    /// streams into the shared menu VM and stays viewable from the menu's Result
    /// window, without stealing focus from the foreground app.
    private let presentResult: @MainActor () -> Void

    init(
        viewModel: PadViewModel,
        layoutID: UUID,
        presentResult: @escaping @MainActor () -> Void
    ) {
        self.viewModel = viewModel
        self.layoutID = layoutID
        self.presentResult = presentResult
    }

    var body: some View {
        Group {
            if let layout = viewModel.response.layouts.first(where: { $0.id == layoutID }) {
                grid(for: layout)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
            }
        }
        .task { await viewModel.load() }
        .actionErrorAlert($viewModel.actionError)
    }

    @ViewBuilder
    private func grid(for layout: PadLayoutResponse) -> some View {
        PadGridView(
            layout: layout,
            cells: viewModel.cells(forLayout: layout.id),
            isEditMode: false,
            viewModel: viewModel,
            onActivate: { cell in onActivate(cell) },
            onEditCell: { _ in },
            onDeleteCell: { _ in },
            onEditEmptyCell: { _, _ in }
        )
    }

    /// Runs the cell, and — for a `.runAndStream` cell — asks the host to surface
    /// the live output (the SwiftUI Window host fronts the Result window; the
    /// non-activating panel host no-ops to avoid stealing focus).
    private func onActivate(_ cell: PadCellResponse) {
        Task { await viewModel.activateCell(cell) }
        if viewModel.isStreaming(cell) {
            presentResult()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Launcher Pad", systemImage: "rectangle.grid.2x2")
        } description: {
            Text("Create a pad in Settings → Pads to get started.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
