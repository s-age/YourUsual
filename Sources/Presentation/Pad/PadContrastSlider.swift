import SwiftUI

/// A pad slider drawn entirely in SwiftUI (no AppKit) so the thumb colour can follow the
/// cell's background contrast — the stock `Slider`'s knob colour is not settable, so it stays
/// white and vanishes on a light cell. Supports horizontal and vertical orientations.
///
/// Drag handling mirrors the stock `Slider`'s callback shape: `onValueChanged` fires
/// continuously while dragging (value quantised to `step`) so the caller can run the slider's
/// command throttled; `onEditingEnded` fires once on release with the final value (the
/// equivalent of `onEditingChanged(false)`) for the tail run + persist.
struct PadContrastSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let orientation: SliderOrientation
    /// Track tint; the cell passes its contrast foreground so the bar reads on any background.
    let tint: Color
    /// Thumb fill; same contrast colour. Solid over the semi-transparent fill so it stands out.
    let thumbColour: Color
    let onValueChanged: (Double) -> Void
    let onEditingEnded: (Double) -> Void

    private let thumbDiameter: CGFloat = 20
    private let trackThickness: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let isHorizontal = orientation == .horizontal
            let length = (isHorizontal ? proxy.size.width : proxy.size.height)
            let usable = max(length - thumbDiameter, 1)
            let fraction = fraction(for: value)
            // Thumb-centre distance from the leading (horizontal) / bottom (vertical) edge.
            let thumbOffset = thumbDiameter / 2 + fraction * usable

            ZStack(alignment: isHorizontal ? .leading : .bottom) {
                if isHorizontal {
                    Capsule().fill(tint.opacity(0.25)).frame(height: trackThickness)
                    Capsule().fill(tint.opacity(0.55)).frame(width: thumbOffset, height: trackThickness)
                } else {
                    Capsule().fill(tint.opacity(0.25)).frame(width: trackThickness)
                    Capsule().fill(tint.opacity(0.55)).frame(width: trackThickness, height: thumbOffset)
                }
                Circle()
                    .fill(thumbColour)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .shadow(radius: 1, y: 0.5)
                    .position(
                        x: isHorizontal ? thumbOffset : proxy.size.width / 2,
                        y: isHorizontal ? proxy.size.height / 2 : proxy.size.height - thumbOffset
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let pos = isHorizontal ? gesture.location.x : gesture.location.y
                        // Vertical runs bottom→top, so invert the fraction.
                        let raw = isHorizontal
                            ? (pos - thumbDiameter / 2) / usable
                            : 1 - (pos - thumbDiameter / 2) / usable
                        let stepped = quantise(fraction: raw)
                        if stepped != value {
                            value = stepped
                            onValueChanged(stepped)
                        }
                    }
                    .onEnded { _ in onEditingEnded(value) }
            )
        }
        // Pin the cross axis to the thumb size; the main axis fills the space it is given.
        .frame(
            width: orientation == .vertical ? thumbDiameter : nil,
            height: orientation == .horizontal ? thumbDiameter : nil
        )
    }

    /// Current value as a 0...1 position along the track.
    private func fraction(for value: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    /// Maps a raw 0...1 drag position back to a value snapped to `step` and clamped to range.
    private func quantise(fraction: Double) -> Double {
        let clamped = min(max(fraction, 0), 1)
        let raw = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
        let stepped = (raw / step).rounded() * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }
}
