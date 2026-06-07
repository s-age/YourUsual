import XCTest
@testable import YourUsual

final class PadCellTests: XCTestCase {

    /// Builds a cell with sensible defaults; tests override only the geometry they exercise.
    private func makeCell(column: Int, row: Int, columnSpan: Int = 1, rowSpan: Int = 1) -> PadCell {
        PadCell(
            id: UUID(), layoutID: UUID(),
            column: column, row: row,
            columnSpan: columnSpan, rowSpan: rowSpan,
            entryID: nil, backgroundColor: nil, customIconName: nil, customLabel: nil
        )
    }

    // MARK: - covers(column:row:)

    func test_covers_atOrigin_isTrue() {
        let cell = makeCell(column: 2, row: 3)
        XCTAssertTrue(cell.covers(column: 2, row: 3))
    }

    func test_covers_neighbouringSquareOfUnitCell_isFalse() {
        let cell = makeCell(column: 2, row: 3)
        XCTAssertFalse(cell.covers(column: 3, row: 3))
    }

    func test_covers_interiorSquareOfSpan_isTrue() {
        let cell = makeCell(column: 1, row: 1, columnSpan: 2, rowSpan: 2)
        XCTAssertTrue(cell.covers(column: 2, row: 2))
    }

    func test_covers_squareJustPastSpan_isFalse() {
        let cell = makeCell(column: 1, row: 1, columnSpan: 2, rowSpan: 2)
        XCTAssertFalse(cell.covers(column: 3, row: 1))
    }

    func test_covers_squareBeforeOrigin_isFalse() {
        let cell = makeCell(column: 2, row: 2, columnSpan: 2, rowSpan: 2)
        XCTAssertFalse(cell.covers(column: 1, row: 2))
    }

    // MARK: - fits(inColumns:rows:)

    func test_fits_unitCellAtOrigin_isTrue() {
        let cell = makeCell(column: 0, row: 0)
        XCTAssertTrue(cell.fits(inColumns: 8, rows: 8))
    }

    func test_fits_unitCellAtLastSquare_isTrue() {
        let cell = makeCell(column: 7, row: 7)
        XCTAssertTrue(cell.fits(inColumns: 8, rows: 8))
    }

    func test_fits_spanOverflowingRightEdge_isFalse() {
        let cell = makeCell(column: 7, row: 0, columnSpan: 2, rowSpan: 1)
        XCTAssertFalse(cell.fits(inColumns: 8, rows: 8))
    }

    func test_fits_spanOverflowingBottomEdge_isFalse() {
        let cell = makeCell(column: 0, row: 7, columnSpan: 1, rowSpan: 2)
        XCTAssertFalse(cell.fits(inColumns: 8, rows: 8))
    }

    func test_fits_negativeOrigin_isFalse() {
        let cell = makeCell(column: -1, row: 0)
        XCTAssertFalse(cell.fits(inColumns: 8, rows: 8))
    }

    func test_fits_spanFlushWithEdges_isTrue() {
        let cell = makeCell(column: 6, row: 6, columnSpan: 2, rowSpan: 2)
        XCTAssertTrue(cell.fits(inColumns: 8, rows: 8))
    }

    // MARK: - overlaps(_:)

    func test_overlaps_sameOrigin_isTrue() {
        let a = makeCell(column: 2, row: 2)
        let b = makeCell(column: 2, row: 2)
        XCTAssertTrue(a.overlaps(b))
    }

    func test_overlaps_horizontallyAdjacentUnitCells_isFalse() {
        let a = makeCell(column: 0, row: 0)
        let b = makeCell(column: 1, row: 0)
        XCTAssertFalse(a.overlaps(b))
    }

    func test_overlaps_spanReachingIntoNeighbour_isTrue() {
        let wide = makeCell(column: 0, row: 0, columnSpan: 2, rowSpan: 1)
        let neighbour = makeCell(column: 1, row: 0)
        XCTAssertTrue(wide.overlaps(neighbour))
    }

    func test_overlaps_diagonallyTouchingUnitCells_isFalse() {
        let a = makeCell(column: 0, row: 0)
        let b = makeCell(column: 1, row: 1)
        XCTAssertFalse(a.overlaps(b))
    }

    func test_overlaps_isSymmetric() {
        let wide = makeCell(column: 0, row: 0, columnSpan: 2, rowSpan: 1)
        let neighbour = makeCell(column: 1, row: 0)
        XCTAssertEqual(wide.overlaps(neighbour), neighbour.overlaps(wide))
    }
}
