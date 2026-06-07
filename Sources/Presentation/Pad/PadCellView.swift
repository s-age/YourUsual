import SwiftUI

struct PadCellView: View {
    let cell: PadCellResponse
    let isEditMode: Bool
    /// Drives a live slider cell's drag intents. Unused by button cells; threaded down so
    /// the kind branch in `body` can hand it to `PadSliderCellView`.
    let viewModel: PadViewModel
    let onActivate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var backgroundColour: Color {
        guard let hex = cell.backgroundColor, let colour = Color(hex: hex) else {
            return Color.secondary.opacity(0.15)
        }
        return colour
    }

    /// Icon/label colour, auto-picked for contrast against the cell background by
    /// luminance (black on light cells, white on dark). Falls back to `.primary` for
    /// the default no-colour cell. Photo icons are bitmaps and ignore this tint; only
    /// the SF Symbol glyph and the label text follow it.
    private var foregroundColour: Color {
        guard let hex = cell.backgroundColor, let colour = Color.readableForeground(onHex: hex) else {
            return .primary
        }
        return colour
    }

    /// Height of the icon row, shared by every icon variant (SF Symbol, app icon, custom
    /// image). Sized to the SF Symbol's optical box: the image variants are matched *down* to
    /// it (rather than the symbols up to a larger thumbnail) so every cell's label sits on the
    /// same baseline as the symbol-only cells.
    private var iconSize: CGFloat { 40 }

    /// SF Symbol point size. The 0.84 factor keeps the glyph at its prior ≈33.6pt optical size
    /// (when the box was 48) so the symbol cells read unchanged while the box shrank to the
    /// glyph's natural height.
    private var symbolFont: Font { .system(size: iconSize * 0.84) }

    // SF Symbol shown when there is no image (or it fails to load).
    // Custom override → entry's per-kind SF Symbol → neutral placeholder.
    private var fallbackSymbol: String {
        cell.customIconName
            ?? cell.entry?.kind.iconSystemName   // EntryKind+Presentation
            ?? "square.dashed"
    }

    /// Cached icon URL for the app an "open with app" cell launches with, if resolved.
    /// Mirrors the menu / settings list: a browse cell that opens with a specific app shows
    /// that application's real icon. nil for every other kind (and for the default app).
    private var appIconURL: URL? {
        cell.entry?.kind.appBundleIdentifier
            .flatMap { viewModel.appIconURL(forBundleIdentifier: $0) }
    }

    /// Icon precedence: a user-set custom image, then a user-set custom SF Symbol, then the
    /// auto-resolved application icon (for "open with app" cells), then the entry's per-kind
    /// SF Symbol. A user customisation always wins over the auto app icon.
    @ViewBuilder private var icon: some View {
        if let url = cell.customIconImageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    Image(systemName: fallbackSymbol).font(symbolFont)
                case .empty:
                    ProgressView().controlSize(.small)
                @unknown default:
                    Image(systemName: fallbackSymbol).font(symbolFont)
                }
            }
            .frame(width: iconSize, height: iconSize)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if cell.customIconName == nil, let url = appIconURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: fallbackSymbol).font(symbolFont)
            }
            .frame(width: iconSize, height: iconSize)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            // Bound the symbol to the shared icon-row height so it shares the image variants'
            // baseline (the glyph stays centred within the box).
            Image(systemName: fallbackSymbol)
                .font(symbolFont)
                .frame(height: iconSize)
        }
    }

    private var label: String {
        cell.customLabel ?? cell.entry?.name ?? ""
    }

    /// A circular corner glyph (delete/edit) shown over a configured cell in edit mode.
    /// Dark fill + white glyph keeps it legible over any cell colour.
    private func badge(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Color.black.opacity(0.45), in: Circle())
    }

    var body: some View {
        cellBody
            .padCellPlacement(PadCellPlacement(
                column: cell.column, row: cell.row,
                columnSpan: cell.columnSpan, rowSpan: cell.rowSpan
            ))
    }

    /// A slider entry renders a live `Slider` in launch mode; everything else (and a slider
    /// in edit mode, where tapping must edit the cell) renders the standard button cell.
    @ViewBuilder private var cellBody: some View {
        if case .slider(let slider)? = cell.entry?.kind, !isEditMode {
            PadSliderCellView(cell: cell, slider: slider, viewModel: viewModel)
        } else {
            buttonCell
        }
    }

    private var buttonCell: some View {
        Button {
            if isEditMode { onEdit() } else { onActivate() }
        } label: {
            VStack(spacing: 4) {
                icon
                if !label.isEmpty {
                    Text(label)
                        .font(.callout)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(foregroundColour)
            .background(backgroundColour, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            if isEditMode {
                Button(action: onDelete) {
                    badge(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isEditMode {
                // Visual affordance only — tapping anywhere on the cell already edits.
                badge(systemName: "pencil")
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .contextMenu {
            if isEditMode {
                Button("Edit", action: onEdit)
                Button("Clear", role: .destructive, action: onDelete)
            }
        }
    }
}
