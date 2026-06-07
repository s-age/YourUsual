import SwiftUI

/// Settings → "Pads" detail pane: edits one launcher pad. Top form tweaks the layout
/// properties (name / columns / rows); the grid below places, edits, and removes cells
/// (always in edit mode — this *is* the editor). Cell mutations route through the shared
/// `PadViewModel`, so the launcher panel reflects them live.
///
/// The parent stamps `.id(layout.id)` on this view so selecting a different pad mints a
/// fresh instance, re-seeding the form `@State` from the newly selected layout.
struct PadEditorView: View {
    @Bindable var viewModel: PadViewModel
    let layout: PadLayoutResponse

    @State private var name: String
    @State private var columns: Int
    @State private var rows: Int
    @State private var editingCell: PadCellEditContext?

    init(viewModel: PadViewModel, layout: PadLayoutResponse) {
        self.viewModel = viewModel
        self.layout = layout
        _name = State(initialValue: layout.name)
        _columns = State(initialValue: layout.columns)
        _rows = State(initialValue: layout.rows)
    }

    var body: some View {
        VStack(spacing: 0) {
            form
            Divider()
            grid
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $editingCell) { context in
            PadCellEditSheet(context: context, viewModel: viewModel)
        }
    }

    // MARK: - Layout properties

    @ViewBuilder
    private var form: some View {
        HStack(spacing: 16) {
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
                .onSubmit { Task { await commit() } }

            Stepper("Columns: \(columns)", value: $columns, in: PadLayoutResponse.columnRange)
                .fixedSize()
                .onChange(of: columns) { Task { await commit() } }

            Stepper("Rows: \(rows)", value: $rows, in: PadLayoutResponse.rowRange)
                .fixedSize()
                .onChange(of: rows) { Task { await commit() } }

            Spacer()
        }
        .padding(12)
    }

    /// Persists the layout edits. Falls back to the stored name when the field is blank
    /// (the validation decorator rejects an empty name) so a stepper bump mid-edit can't
    /// fail; the grid prune on shrink is owned by `EditPadLayoutUseCase`.
    private func commit() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveName = trimmed.isEmpty ? layout.name : trimmed
        await viewModel.editLayout(id: layout.id, name: effectiveName, columns: columns, rows: rows)
    }

    // MARK: - Cell grid (always editable)

    @ViewBuilder
    private var grid: some View {
        PadGridView(
            layout: layout,
            cells: viewModel.cells(forLayout: layout.id),
            isEditMode: true,
            viewModel: viewModel,
            onActivate: { _ in },   // editor: tapping a cell edits it (handled by onEditCell)
            onEditCell: { cell in editingCell = PadCellEditContext(layout: layout, existing: cell) },
            onDeleteCell: { cell in
                Task {
                    await viewModel.deleteCell(layoutID: layout.id, column: cell.column, row: cell.row,
                                               iconImageName: cell.customIconImageName)
                }
            },
            onEditEmptyCell: { col, row in
                editingCell = PadCellEditContext(layout: layout, column: col, row: row, existing: nil)
            }
        )
    }
}
