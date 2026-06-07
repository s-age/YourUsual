import SwiftUI

/// A live slider cell in launch mode: dragging runs the slider's command throttled, and
/// releasing commits the final value (run + persist). Rendered by `PadContrastSlider` (a
/// pure-SwiftUI control) so the track/thumb colour follows the cell background contrast and
/// the orientation (horizontal/vertical) can be honoured — the stock `Slider` allows neither.
/// `onValueChanged` drives the throttled run; `onEditingEnded` commits the tail value.
struct PadSliderCellView: View {
    let cell: PadCellResponse
    let slider: SliderPayload
    let viewModel: PadViewModel
    @State private var value: Double

    init(cell: PadCellResponse, slider: SliderPayload, viewModel: PadViewModel) {
        self.cell = cell
        self.slider = slider
        self.viewModel = viewModel
        _value = State(initialValue: slider.currentValue)
    }

    /// Cell background — reuses the configured colour band as a visual identifier, falling
    /// back to the neutral cell fill (mirrors `PadCellView.backgroundColour`).
    private var backgroundColour: Color {
        guard let hex = cell.backgroundColor, let colour = Color(hex: hex) else {
            return Color.secondary.opacity(0.15)
        }
        return colour
    }

    /// Label/value text colour, auto-picked for contrast against the cell background by
    /// luminance (mirrors `PadCellView.foregroundColour`). Falls back to `.secondary` for
    /// the default no-colour cell so the text stays muted against the neutral fill.
    private var foregroundColour: Color {
        guard let hex = cell.backgroundColor, let colour = Color.readableForeground(onHex: hex) else {
            return .secondary
        }
        return colour
    }

    var body: some View {
        content
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(backgroundColour, in: RoundedRectangle(cornerRadius: 8))
            // `@State value` is only seeded at init; for the same cell id it would otherwise
            // ignore a `currentValue` refreshed by an external reload. Drag is the usual source,
            // but follow external changes too so the knob never shows a stale position.
            .onChange(of: slider.currentValue) { _, newValue in value = newValue }
    }

    /// Layout differs by orientation: a horizontal slider stacks label / track / value with
    /// the track at its natural height; a vertical slider lets the track fill the cell's
    /// height between the label and value.
    @ViewBuilder private var content: some View {
        switch cell.sliderOrientation {
        case .horizontal:
            VStack(spacing: 2) {
                labelView
                sliderControl
                valueView
            }
        case .vertical:
            VStack(spacing: 4) {
                labelView
                sliderControl.frame(maxHeight: .infinity)
                valueView
            }
        }
    }

    @ViewBuilder private var labelView: some View {
        if let label = labelText {
            Text(label)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(foregroundColour)
        }
    }

    private var valueView: some View {
        Text(SliderValueFormatter.format(value, step: slider.step))
            .font(.caption2)
            .foregroundStyle(foregroundColour)
            .monospacedDigit()
    }

    /// Custom contrast slider: the thumb/track follow `foregroundColour` so they stay visible
    /// on any cell background. Dragging runs the command throttled; releasing commits the tail
    /// value (run + persist) — the same intents the stock `Slider` drove before.
    private var sliderControl: some View {
        PadContrastSlider(
            value: $value,
            range: slider.minValue...slider.maxValue,
            step: slider.step,
            orientation: cell.sliderOrientation,
            tint: foregroundColour,
            thumbColour: foregroundColour,
            onValueChanged: { viewModel.adjustSlider(cell: cell, value: $0) },
            onEditingEnded: { viewModel.commitSlider(cell: cell, value: $0) }
        )
    }

    /// Slider cells hide icon/label by domain rule, but a custom label (if the user set one)
    /// still helps identify which slider is which; otherwise fall back to the entry name.
    private var labelText: String? {
        let text = cell.customLabel ?? cell.entry?.name
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}
