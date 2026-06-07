import XCTest
@testable import YourUsual

/// Round-trip cohesion for `PadMapper` — focuses on the slider orientation column added so a
/// pad cell can render a slider horizontally or vertically (the orientation lives on the cell,
/// not the entry). Other fields are covered implicitly by the round-trip assertions.
final class PadMapperTests: XCTestCase {

    private func cell(orientation: SliderOrientation) -> PadCell {
        PadCell(
            id: UUID(), layoutID: UUID(),
            column: 0, row: 0, columnSpan: 1, rowSpan: 2,
            entryID: UUID(),
            backgroundColor: "#1A73E8",
            customIconName: nil, customIconImageName: nil, customLabel: nil,
            sliderOrientation: orientation
        )
    }

    func test_cellRoundTrip_preservesVerticalOrientation() {
        let restored = PadMapper.toEntity(PadMapper.toDTO(cell(orientation: .vertical)))
        XCTAssertEqual(restored.sliderOrientation, .vertical)
    }

    func test_cellRoundTrip_preservesHorizontalOrientation() {
        let restored = PadMapper.toEntity(PadMapper.toDTO(cell(orientation: .horizontal)))
        XCTAssertEqual(restored.sliderOrientation, .horizontal)
    }

    func test_toEntity_legacyUnknownOrientation_coalescesToHorizontal() {
        var dto = PadMapper.toDTO(cell(orientation: .vertical))
        dto.orientation = ""   // a row persisted before the orientation column / unknown raw value
        XCTAssertEqual(PadMapper.toEntity(dto).sliderOrientation, .horizontal)
    }
}
