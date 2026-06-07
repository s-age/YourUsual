import SwiftUI

/// Maps the crop editor's view-space transform (zoom + drag offset over a square
/// viewport) into a square crop rectangle in the **source image's pixel coordinates**.
///
/// Pure and free-standing so the pixel math is unit-testable in isolation (signs and
/// coefficients are pinned by tests; tune against the device, then lock them in).
///
/// At `zoom == 1` the image is aspect-filled: its short side fits the viewport and the
/// long side overflows, so the visible square is `min(width, height)` px. Zooming in
/// shrinks the crop; dragging moves its centre (the image moves under a fixed viewport,
/// so the crop centre moves opposite to the offset).
func cropRect(zoom: CGFloat, offset: CGSize, viewport: CGFloat,
              size: IconImageSizeResponse) -> PadIconCropInput {
    let width = size.width, height = size.height
    let w = CGFloat(width), h = CGFloat(height)
    let safeZoom = max(zoom, 1)
    let fitSide = min(w, h)                     // visible square edge (px) at zoom == 1
    let sideF = (fitSide / safeZoom).rounded()
    let side = min(max(Int(sideF), 1), min(width, height))

    let pxPerPoint = (fitSide / safeZoom) / viewport
    let centerX = w / 2 - offset.width * pxPerPoint
    let centerY = h / 2 - offset.height * pxPerPoint

    let originX = clampInt((centerX - CGFloat(side) / 2).rounded(), 0, width - side)
    let originY = clampInt((centerY - CGFloat(side) / 2).rounded(), 0, height - side)
    return PadIconCropInput(originX: originX, originY: originY, side: side)
}

private func clampInt(_ value: CGFloat, _ low: Int, _ high: Int) -> Int {
    min(max(Int(value), low), max(low, high))
}

/// Chat-app-style square cropper: drag the image to recentre, pinch or use the slider to
/// zoom. On confirm it computes the pixel crop via `cropRect` and hands it back.
struct PadIconCropEditor: View {
    let sourcePath: String
    let size: IconImageSizeResponse
    let onCommit: (PadIconCropInput) -> Void

    @Environment(\.dismiss) private var dismiss

    private let viewport: CGFloat = 240

    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero

    private var effectiveZoom: CGFloat { max(zoom * pinch, 1) }
    private var effectiveOffset: CGSize {
        CGSize(width: offset.width + drag.width, height: offset.height + drag.height)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Adjust Icon").font(.headline)

            AsyncImage(url: URL(filePath: sourcePath)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                        .scaleEffect(effectiveZoom)
                        .offset(effectiveOffset)
                case .failure:
                    Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
                default:
                    ProgressView()
                }
            }
            .frame(width: viewport, height: viewport)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .updating($pinch) { value, state, _ in state = value }
                    .onEnded { value in zoom = max(zoom * value, 1) }
            )

            Slider(value: $zoom, in: 1...4) { Text("Zoom") }
                .frame(width: viewport)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Use Image") {
                    onCommit(cropRect(zoom: effectiveZoom, offset: effectiveOffset,
                                      viewport: viewport, size: size))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .frame(width: viewport)
        }
        .padding(20)
    }
}
