import SwiftUI
import UniformTypeIdentifiers

/// Identifiable wrapper so a probed source image can drive `.sheet(item:)` for the cropper.
private struct CropContext: Identifiable {
    let id = UUID()
    let path: String
    let size: IconImageSizeResponse
}

/// The two mutually-exclusive icon sources. A cell uses *either* a cropped image *or*
/// an SF Symbol name — never both — so the form picks one and clears the other on save.
private enum IconSource: String, CaseIterable, Identifiable {
    case image  = "Image"
    case symbol = "SF Symbol"
    var id: Self { self }
}

/// The kind of cell being placed. A button cell links a normal entry and renders an
/// icon+label tap target; a slider cell links a slider entry and renders a draggable
/// control — vertical or horizontal. Whether the cell *is* a slider follows its linked
/// entry's kind; *which orientation* is the Pad's own choice, persisted on the cell
/// (`PadCell.sliderOrientation`), so the same slider command can be placed either way.
private enum CellKind: String, CaseIterable, Identifiable {
    case button = "Button"
    case sliderVertical = "Slider (Vertical)"
    case sliderHorizontal = "Slider (Horizontal)"
    var id: Self { self }

    /// The orientation this cell persists when it is a slider; nil for a button.
    var sliderOrientation: SliderOrientation? {
        switch self {
        case .button: return nil
        case .sliderVertical: return .vertical
        case .sliderHorizontal: return .horizontal
        }
    }
    var isSlider: Bool { sliderOrientation != nil }
}

struct PadCellEditSheet: View {
    let context: PadCellEditContext
    let viewModel: PadViewModel

    @State private var cellKind: CellKind = .button
    @State private var selectedEntryID: UUID?
    @State private var columnSpan: Int = 1
    @State private var rowSpan: Int = 1
    @State private var hasBackgroundColor: Bool = false
    @State private var backgroundHex: String = PadColorPalette.defaultSwatch
    @State private var customIconName: String = ""
    @State private var customLabel: String = ""
    @State private var iconSource: IconSource = .image

    // Image-icon state.
    @State private var iconImageName: String?          // existing/imported filename
    @State private var previousIconImageName: String?  // name at populate time (cleanup)
    @State private var newIconSourcePath: String?      // source awaiting import
    @State private var newIconCrop: PadIconCropInput?  // crop awaiting import
    @State private var showingImporter = false
    @State private var cropContext: CropContext?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.self) private var environment

    var body: some View {
        Form {
            Section("Type") {
                Picker("Type", selection: $cellKind) {
                    ForEach(CellKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Entry") {
                Picker("Entry", selection: $selectedEntryID) {
                    Text("(none)").tag(Optional<UUID>.none)
                    ForEach(filteredEntries) { entry in
                        Label(entry.name, systemImage: entry.kind.iconSystemName)
                            .tag(Optional(entry.id))
                    }
                }
            }

            Section("Span") {
                // A horizontal slider needs ≥2 columns (lower bound 2); a vertical slider is
                // pinned to a single column, so it hides the Columns stepper entirely.
                if !isVerticalSlider {
                    Stepper("Columns: \(columnSpan)", value: $columnSpan,
                            in: columnLowerBound...max(columnLowerBound,
                                                       context.layout.columns - context.column))
                }
                // A horizontal slider is pinned to a single row (hides Rows); a vertical slider
                // needs ≥2 rows (lower bound 2); a button is unconstrained.
                if !isHorizontalSlider {
                    Stepper("Rows: \(rowSpan)", value: $rowSpan,
                            in: rowLowerBound...max(rowLowerBound,
                                                    context.layout.rows - context.row))
                }
            }

            Section("Appearance") {
                Toggle("Custom background colour", isOn: $hasBackgroundColor)
                if hasBackgroundColor {
                    ColorPicker("Background colour", selection: backgroundColourBinding,
                                supportsOpacity: false)
                }
                // A slider renders its own track + value readout, so it carries no icon
                // or label override — only the background colour band identifies it.
                if !cellKind.isSlider {
                    Picker("Icon", selection: $iconSource) {
                        ForEach(IconSource.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch iconSource {
                    case .image:  imagePicker
                    case .symbol: TextField("SF Symbol icon name", text: $customIconName)
                    }
                    TextField("Label override", text: $customLabel)
                }
            }
        }
        .formStyle(.grouped)
        // Pin Cancel/Save to a fixed footer so they stay visible without scrolling
        // the form to the bottom — the action bar must never be off-screen.
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.bar)
        }
        .onAppear { populate() }
        .onChange(of: cellKind) {
            // Switching type narrows the entry list; drop the selection if it no longer
            // matches (a slider cell can't keep a button entry, and vice versa). The type also
            // fixes the orientation, which changes the span bounds (horizontal → ≥2 cols / 1
            // row; vertical → 1 col / ≥2 rows), so lift the spans back in-range.
            if let id = selectedEntryID, !filteredEntries.contains(where: { $0.id == id }) {
                selectedEntryID = nil
            }
            clampSpansToBounds()
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            // No security scope needed — the app is unsandboxed. Probe, then crop.
            Task {
                if let size = await viewModel.probeIcon(path: url.path) {
                    cropContext = CropContext(path: url.path, size: size)
                }
            }
        }
        .sheet(item: $cropContext) { ctx in
            PadIconCropEditor(sourcePath: ctx.path, size: ctx.size) { crop in
                newIconSourcePath = ctx.path
                newIconCrop = crop
                iconImageName = nil   // new import supersedes any existing name on save
            }
        }
    }

    /// Entries offered by the picker for the current type: slider entries when placing a
    /// slider cell, every other kind when placing a button. Keeps the selected entry's kind
    /// always consistent with `cellKind` (so the Domain's `linkedEntryKind` check can't fail).
    private var filteredEntries: [SavedEntryResponse] {
        viewModel.entries.filter { entry in
            if case .slider = entry.kind { return cellKind.isSlider }
            return !cellKind.isSlider
        }
    }

    /// Orientation the chosen type will persist (driven by the Type picker, not the entry).
    private var isHorizontalSlider: Bool { cellKind.sliderOrientation == .horizontal }
    private var isVerticalSlider: Bool { cellKind.sliderOrientation == .vertical }

    /// Span lower bounds: a horizontal slider needs ≥2 columns; a vertical slider needs ≥2 rows.
    private var columnLowerBound: Int { isHorizontalSlider ? 2 : 1 }
    private var rowLowerBound: Int { isVerticalSlider ? 2 : 1 }

    /// Lift the column/row spans up to the current type's minimums so the steppers stay in
    /// range after the type or selected entry (and thus the bounds) changes.
    private func clampSpansToBounds() {
        columnSpan = max(columnSpan, columnLowerBound)
        rowSpan = max(rowSpan, rowLowerBound)
    }

    @ViewBuilder private var imagePicker: some View {
        if newIconSourcePath != nil {
            Text("New image selected").font(.caption).foregroundStyle(.secondary)
        } else if iconImageName != nil {
            Text("Image set").font(.caption).foregroundStyle(.secondary)
        }
        HStack {
            Spacer()
            Button("Choose Image…") { showingImporter = true }
            if iconImageName != nil || newIconSourcePath != nil {
                Button("Remove Image", role: .destructive) {
                    iconImageName = nil
                    newIconSourcePath = nil
                    newIconCrop = nil
                }
            }
        }
    }

    /// Bridges the hex-stored `backgroundHex` to `ColorPicker`'s `Color` binding. Reading
    /// falls back to the default swatch for an unparseable hex; writing resolves the picked
    /// colour back to `#RRGGBB`. The picker opens the system colour panel in a separate
    /// window, which the Settings `Window` (a normal key window) can host.
    private var backgroundColourBinding: Binding<Color> {
        Binding(
            get: { Color(hex: backgroundHex) ?? Color(hex: PadColorPalette.defaultSwatch) ?? .blue },
            set: { backgroundHex = $0.hexRGB(in: environment) }
        )
    }

    private func save() {
        // Exclusive icon source: send only the selected side, nil the other. Switching
        // away from an image yields a nil image name; the use case then deletes the
        // superseded PNG (it compares against `previousIconImageName`).
        // A slider cell carries no icon or label override and is pinned on its short axis
        // (horizontal → 1 row, vertical → 1 column); the Domain enforces this too, but we
        // send a clean payload so nothing lingers.
        let isSlider  = cellKind.isSlider
        let useImage  = !isSlider && iconSource == .image
        let useSymbol = !isSlider && iconSource == .symbol
        let resolvedColumnSpan = isVerticalSlider ? 1 : columnSpan
        let resolvedRowSpan    = isHorizontalSlider ? 1 : rowSpan
        Task {
            let saved = await viewModel.saveCell(SavePadCellRequest(
                layoutID: context.layout.id,
                column: context.column,
                row: context.row,
                columnSpan: resolvedColumnSpan,
                rowSpan: resolvedRowSpan,
                entryID: selectedEntryID,
                backgroundColor: hasBackgroundColor ? backgroundHex : nil,
                customIconName: useSymbol && !customIconName.isEmpty ? customIconName : nil,
                customLabel: isSlider || customLabel.isEmpty ? nil : customLabel,
                sliderOrientation: cellKind.sliderOrientation ?? .horizontal,
                customIconImageName: useImage && newIconSourcePath == nil ? iconImageName : nil,
                newIconSourcePath: useImage ? newIconSourcePath : nil,
                newIconCrop: useImage ? newIconCrop : nil,
                previousIconImageName: previousIconImageName
            ))
            if saved { dismiss() }   // keep the sheet open on rejection so input survives
        }
    }

    private func populate() {
        if let cell = context.existing {
            // Seed the type from the linked entry's kind + the cell's stored orientation,
            // before the selection, so the `cellKind` onChange (which drops a now-filtered
            // selection) sees the matching entry already in range and keeps it.
            if case .slider? = cell.entry?.kind {
                cellKind = cell.sliderOrientation == .vertical ? .sliderVertical : .sliderHorizontal
            } else {
                cellKind = .button
            }
            selectedEntryID     = cell.entryID
            columnSpan          = cell.columnSpan
            rowSpan             = cell.rowSpan
            if let hex = cell.backgroundColor {
                hasBackgroundColor = true
                backgroundHex      = hex
            }
            customIconName      = cell.customIconName ?? ""
            customLabel         = cell.customLabel ?? ""
            iconImageName         = cell.customIconImageName
            previousIconImageName = cell.customIconImageName
            // Reflect which source the saved cell used; both empty keeps the default.
            if cell.customIconImageName != nil {
                iconSource = .image
            } else if let name = cell.customIconName, !name.isEmpty {
                iconSource = .symbol
            }
        }
    }
}
