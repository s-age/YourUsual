import XCTest
import SwiftUI
@testable import YourUsual

/// Pins the `cropRect` pixel math (signs + coefficients) against regressions. The view
/// gestures are not unit-tested; the pure mapping is.
final class PadIconCropEditorTests: XCTestCase {

    private func size(_ w: Int, _ h: Int) -> IconImageSizeResponse {
        IconImageSizeResponse(width: w, height: h)
    }

    // zoom 1, no offset → centre-fit crop. Square image: the whole image.
    func test_cropRect_squareImage_zoom1_noOffset_coversWholeImage() {
        let crop = cropRect(zoom: 1, offset: .zero, viewport: 240, size: size(512, 512))
        XCTAssertEqual(crop, PadIconCropInput(originX: 0, originY: 0, side: 512))
    }

    // Landscape: short side (height) is the visible square; it is centred horizontally.
    func test_cropRect_landscape_zoom1_noOffset_centresShortSide() {
        let crop = cropRect(zoom: 1, offset: .zero, viewport: 240, size: size(400, 200))
        XCTAssertEqual(crop, PadIconCropInput(originX: 100, originY: 0, side: 200))
    }

    // Portrait: short side (width) is the visible square; it is centred vertically.
    func test_cropRect_portrait_zoom1_noOffset_centresShortSide() {
        let crop = cropRect(zoom: 1, offset: .zero, viewport: 240, size: size(200, 400))
        XCTAssertEqual(crop, PadIconCropInput(originX: 0, originY: 100, side: 200))
    }

    // Zooming in halves the crop side and keeps it centred.
    func test_cropRect_squareImage_zoom2_halvesSideCentred() {
        let crop = cropRect(zoom: 2, offset: .zero, viewport: 240, size: size(512, 512))
        XCTAssertEqual(crop.side, 256)
        XCTAssertEqual(crop.originX, 128)
        XCTAssertEqual(crop.originY, 128)
    }

    // A positive drag offset moves the crop centre in the negative direction (image
    // moves under a fixed viewport), and the origin clamps to image bounds.
    func test_cropRect_offsetClampsWithinBounds() {
        let crop = cropRect(zoom: 1, offset: CGSize(width: 10_000, height: 0),
                            viewport: 240, size: size(512, 512))
        XCTAssertEqual(crop.originX, 0)   // clamped at the left edge
        XCTAssertEqual(crop.side, 512)
    }
}
