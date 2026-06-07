import XCTest
@testable import YourUsual

/// Read-only mocks — `PadService`'s pure-transform methods
/// (`makePadCell`/`applyingCellChange`/`prunedCells`/`removingCell`) never touch the
/// repositories, but the initialiser requires them.
private final class MockPadLayoutRepository: PadLayoutRepositoryProtocol, @unchecked Sendable {
    var listAllResult: [PadLayout] = []
    func listAll() async throws -> [PadLayout] { listAllResult }
}

private final class MockPadCellRepository: PadCellRepositoryProtocol, @unchecked Sendable {
    var listResult: [PadCell] = []
    func list(forLayout layoutID: UUID) async throws -> [PadCell] { listResult }
    func listAll() async throws -> [PadCell] { listResult }
}

/// Spy over the icon repository — records calls + arguments so the delegating
/// `PadService` icon methods can be verified at the protocol boundary.
private final class MockPadIconRepository: PadIconRepositoryProtocol, @unchecked Sendable {
    var directoryResult = URL(filePath: "/tmp/PadIcons")
    var probeResult = PixelSize(width: 100, height: 80)
    var importResult = "imported.png"

    var probeArg: URL?
    var importArg: (source: URL, crop: IconCrop)?
    var deleteArg: String?

    func directory() async throws -> URL { directoryResult }
    func probeSize(source: URL) async throws -> PixelSize { probeArg = source; return probeResult }
    func importIcon(source: URL, crop: IconCrop) async throws -> String {
        importArg = (source, crop); return importResult
    }
    func deleteIcon(name: String) async throws { deleteArg = name }
}

final class PadServiceTests: XCTestCase {
    private var sut: PadService!
    private var iconRepository: MockPadIconRepository!

    override func setUp() {
        super.setUp()
        iconRepository = MockPadIconRepository()
        sut = PadService(
            layoutRepository: MockPadLayoutRepository(),
            cellRepository: MockPadCellRepository(),
            iconRepository: iconRepository
        )
    }

    override func tearDown() {
        sut = nil
        iconRepository = nil
        super.tearDown()
    }

    private func layout(columns: Int = 4, rows: Int = 4) -> PadLayout {
        PadLayout(id: UUID(), name: "Pad", columns: columns, rows: rows, sortIndex: 0)
    }

    private func cell(column: Int, row: Int, columnSpan: Int = 1, rowSpan: Int = 1) -> PadCell {
        PadCell(
            id: UUID(), layoutID: UUID(),
            column: column, row: row,
            columnSpan: columnSpan, rowSpan: rowSpan,
            entryID: nil, backgroundColor: nil, customIconName: nil, customLabel: nil
        )
    }

    private func draft(column: Int, row: Int, columnSpan: Int = 1, rowSpan: Int = 1) -> PadCellDraft {
        PadCellDraft(
            column: column, row: row,
            columnSpan: columnSpan, rowSpan: rowSpan,
            entryID: nil, backgroundColor: nil, customIconName: nil, customLabel: nil
        )
    }

    // MARK: - makePadLayout / updatingPadLayout: name normalization

    func test_makePadLayout_trimsName() {
        let result = sut.makePadLayout(name: "  Pad  ", columns: 4, rows: 3, sortIndex: 0)
        XCTAssertEqual(result.name, "Pad")
    }

    func test_updatingPadLayout_trimsName() {
        let existing = layout()
        let result = sut.updatingPadLayout(existing, name: "  Renamed  ", columns: 4, rows: 3)
        XCTAssertEqual(result.name, "Renamed")
    }

    // MARK: - makePadCell(layoutID:draft:fitting:)

    func test_makePadCell_withinBounds_returnsCellAtOrigin() throws {
        let layoutID = UUID()
        let cell = try sut.makePadCell(
            layoutID: layoutID, draft: draft(column: 1, row: 1), fitting: layout(), linkedEntryKind: nil)
        XCTAssertEqual([cell.column, cell.row], [1, 1])
    }

    func test_makePadCell_carriesLayoutID() throws {
        let layoutID = UUID()
        let cell = try sut.makePadCell(
            layoutID: layoutID, draft: draft(column: 0, row: 0), fitting: layout(), linkedEntryKind: nil)
        XCTAssertEqual(cell.layoutID, layoutID)
    }

    func test_makePadCell_clampsZeroSpanToOne() throws {
        let cell = try sut.makePadCell(
            layoutID: UUID(), draft: draft(column: 0, row: 0, columnSpan: 0, rowSpan: 0),
            fitting: layout(), linkedEntryKind: nil)
        XCTAssertEqual([cell.columnSpan, cell.rowSpan], [1, 1])
    }

    func test_makePadCell_spanOverflowingGrid_throwsInvalidItem() {
        do {
            _ = try sut.makePadCell(
                layoutID: UUID(),
                draft: draft(column: 3, row: 0, columnSpan: 2, rowSpan: 1),
                fitting: layout(columns: 4, rows: 4), linkedEntryKind: nil)
            XCTFail("Expected makePadCell to reject a cell that overflows the grid")
        } catch let error as OperationError {
            guard case .invalidItem = error else {
                return XCTFail("Expected .invalidItem, got \(error)")
            }
        } catch {
            XCTFail("Expected OperationError, got \(error)")
        }
    }

    // MARK: - applyingCellChange(_:newCell:) — overlap rejection (#29 check #3)

    func test_applyingCellChange_intoEmptyGrid_appendsCell() throws {
        let newCell = cell(column: 0, row: 0)
        let result = try sut.applyingCellChange([], newCell: newCell)
        XCTAssertEqual(result.map(\.id), [newCell.id])
    }

    func test_applyingCellChange_nonOverlappingNeighbour_keepsBothCells() throws {
        let existing = cell(column: 0, row: 0)
        let newCell = cell(column: 1, row: 0)
        let result = try sut.applyingCellChange([existing], newCell: newCell)
        XCTAssertEqual(Set(result.map(\.id)), [existing.id, newCell.id])
    }

    func test_applyingCellChange_overlappingDifferentCell_throwsInvalidItem() {
        let existing = cell(column: 1, row: 0)
        let wide = cell(column: 0, row: 0, columnSpan: 2, rowSpan: 1)   // grows into (1,0)
        do {
            _ = try sut.applyingCellChange([existing], newCell: wide)
            XCTFail("Expected applyingCellChange to reject an overlapping placement")
        } catch let error as OperationError {
            guard case .invalidItem = error else {
                return XCTFail("Expected .invalidItem, got \(error)")
            }
        } catch {
            XCTFail("Expected OperationError, got \(error)")
        }
    }

    func test_applyingCellChange_replacingCellAtSameOrigin_doesNotCountAsOverlap() throws {
        let original = cell(column: 2, row: 2)
        let replacement = cell(column: 2, row: 2)   // same origin = the cell being replaced
        let result = try sut.applyingCellChange([original], newCell: replacement)
        XCTAssertEqual(result.map(\.id), [replacement.id])
    }

    // MARK: - prunedCells(_:forNewColumns:newRows:)

    func test_prunedCells_dropsCellsOutsideNewBounds() {
        let kept = cell(column: 0, row: 0)
        let dropped = cell(column: 3, row: 3)
        let result = sut.prunedCells([kept, dropped], forNewColumns: 2, newRows: 2)
        XCTAssertEqual(result.map(\.id), [kept.id])
    }

    func test_prunedCells_keepsAllWhenGridUnchanged() {
        let cells = [cell(column: 0, row: 0), cell(column: 1, row: 1)]
        let result = sut.prunedCells(cells, forNewColumns: 4, newRows: 4)
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - removingCell(at:row:from:)

    func test_removingCell_removesCellAtMatchingOrigin() {
        let target = cell(column: 1, row: 1)
        let other = cell(column: 2, row: 2)
        let result = sut.removingCell(at: 1, row: 1, from: [target, other])
        XCTAssertEqual(result.map(\.id), [other.id])
    }

    func test_removingCell_atEmptyOrigin_leavesCellsUnchanged() {
        let cells = [cell(column: 0, row: 0)]
        let result = sut.removingCell(at: 3, row: 3, from: cells)
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - makePadCell carries the image filename

    func test_makePadCell_carriesCustomIconImageName() throws {
        var d = draft(column: 0, row: 0)
        d.customIconImageName = "abc.png"
        let cell = try sut.makePadCell(layoutID: UUID(), draft: d, fitting: layout(), linkedEntryKind: nil)
        XCTAssertEqual(cell.customIconImageName, "abc.png")
    }

    // MARK: - makePadCell slider geometry rules

    private func sliderKind() -> EntryKind {
        .slider(SliderEntry(commandLine: "echo <VALUE>", minValue: 0, maxValue: 100, step: 1, currentValue: 50))
    }

    /// A draft requesting a vertical slider cell (orientation now lives on the cell, not the entry).
    private func verticalDraft(column: Int, row: Int, columnSpan: Int = 1, rowSpan: Int = 2) -> PadCellDraft {
        var d = draft(column: column, row: row, columnSpan: columnSpan, rowSpan: rowSpan)
        d.sliderOrientation = .vertical
        return d
    }

    func test_makePadCell_slider_forcesRowSpanToOne() throws {
        let cell = try sut.makePadCell(
            layoutID: UUID(), draft: draft(column: 0, row: 0, columnSpan: 2, rowSpan: 3),
            fitting: layout(), linkedEntryKind: sliderKind())
        XCTAssertEqual(cell.rowSpan, 1)
    }

    func test_makePadCell_slider_clampsColumnSpanUpToTwo() throws {
        // columnSpan 2 is the minimum a slider can be saved with; ensure it is preserved
        // (not clamped down) and any larger span is kept.
        let cell = try sut.makePadCell(
            layoutID: UUID(), draft: draft(column: 0, row: 0, columnSpan: 3, rowSpan: 1),
            fitting: layout(), linkedEntryKind: sliderKind())
        XCTAssertEqual(cell.columnSpan, 3)
    }

    func test_makePadCell_slider_columnSpanBelowTwo_throwsInvalidItem() {
        do {
            _ = try sut.makePadCell(
                layoutID: UUID(), draft: draft(column: 0, row: 0, columnSpan: 1, rowSpan: 1),
                fitting: layout(), linkedEntryKind: sliderKind())
            XCTFail("Expected makePadCell to reject a slider narrower than 2 columns")
        } catch let error as OperationError {
            guard case .invalidItem = error else {
                return XCTFail("Expected .invalidItem, got \(error)")
            }
        } catch {
            XCTFail("Expected OperationError, got \(error)")
        }
    }

    func test_makePadCell_slider_dropsIconAndLabel() throws {
        var d = draft(column: 0, row: 0, columnSpan: 2, rowSpan: 1)
        d.customIconName = "star"
        d.customIconImageName = "abc.png"
        d.customLabel = "Label"
        let cell = try sut.makePadCell(
            layoutID: UUID(), draft: d, fitting: layout(), linkedEntryKind: sliderKind())
        XCTAssertNil(cell.customIconName)
        XCTAssertNil(cell.customIconImageName)
        XCTAssertNil(cell.customLabel)
    }

    func test_makePadCell_verticalSlider_forcesColumnSpanToOne() throws {
        let cell = try sut.makePadCell(
            layoutID: UUID(), draft: verticalDraft(column: 0, row: 0, columnSpan: 3, rowSpan: 2),
            fitting: layout(), linkedEntryKind: sliderKind())
        XCTAssertEqual(cell.columnSpan, 1)
    }

    func test_makePadCell_verticalSlider_clampsRowSpanUpToTwo() throws {
        // rowSpan 2 is the minimum a vertical slider can be saved with; a larger span is kept.
        let cell = try sut.makePadCell(
            layoutID: UUID(), draft: verticalDraft(column: 0, row: 0, columnSpan: 1, rowSpan: 3),
            fitting: layout(), linkedEntryKind: sliderKind())
        XCTAssertEqual(cell.rowSpan, 3)
    }

    func test_makePadCell_verticalSlider_rowSpanBelowTwo_throwsInvalidItem() {
        do {
            _ = try sut.makePadCell(
                layoutID: UUID(), draft: verticalDraft(column: 0, row: 0, columnSpan: 1, rowSpan: 1),
                fitting: layout(), linkedEntryKind: sliderKind())
            XCTFail("Expected makePadCell to reject a vertical slider shorter than 2 rows")
        } catch let error as OperationError {
            guard case .invalidItem = error else {
                return XCTFail("Expected .invalidItem, got \(error)")
            }
        } catch {
            XCTFail("Expected OperationError, got \(error)")
        }
    }

    func test_makePadCell_button_keepsRowSpan_regression() throws {
        // linkedEntryKind: nil (button) must not be affected by the slider rules.
        let cell = try sut.makePadCell(
            layoutID: UUID(), draft: draft(column: 0, row: 0, columnSpan: 1, rowSpan: 2),
            fitting: layout(), linkedEntryKind: nil)
        XCTAssertEqual([cell.columnSpan, cell.rowSpan], [1, 2])
    }

    // MARK: - Icon methods delegate to the repository

    func test_probeIconSize_delegatesToRepository() async throws {
        iconRepository.probeResult = PixelSize(width: 640, height: 480)
        let size = try await sut.probeIconSize(source: URL(filePath: "/tmp/in.jpg"))
        XCTAssertEqual(size, PixelSize(width: 640, height: 480))
    }

    func test_importIcon_forwardsSourceAndCrop() async throws {
        let crop = IconCrop(originX: 10, originY: 20, side: 64)
        _ = try await sut.importIcon(source: URL(filePath: "/tmp/in.jpg"), crop: crop)
        XCTAssertEqual(iconRepository.importArg?.crop, crop)
    }

    func test_deleteIcon_forwardsName() async throws {
        try await sut.deleteIcon(name: "old.png")
        XCTAssertEqual(iconRepository.deleteArg, "old.png")
    }

    // MARK: - reordering

    private func namedLayout(_ name: String, sortIndex: Int) -> PadLayout {
        PadLayout(id: UUID(), name: name, columns: 4, rows: 3, sortIndex: sortIndex)
    }

    func test_reordering_renumbersSortIndexToMatchGivenOrder() throws {
        let a = namedLayout("A", sortIndex: 0)
        let b = namedLayout("B", sortIndex: 1)
        let c = namedLayout("C", sortIndex: 2)

        let result = try XCTUnwrap(sut.reordering([a, b, c], orderedIDs: [c.id, a.id, b.id]))

        let index = Dictionary(uniqueKeysWithValues: result.map { ($0.name, $0.sortIndex) })
        XCTAssertEqual(index["C"], 0)
        XCTAssertEqual(index["A"], 1)
        XCTAssertEqual(index["B"], 2)
    }

    func test_reordering_appendsUnmentionedLayoutsAtEnd() throws {
        let a = namedLayout("A", sortIndex: 0)
        let b = namedLayout("B", sortIndex: 1)
        let c = namedLayout("C", sortIndex: 2)

        // Only mention B and C; A should fall to the end.
        let result = try XCTUnwrap(sut.reordering([a, b, c], orderedIDs: [c.id, b.id]))

        let saved = result.sorted { $0.sortIndex < $1.sortIndex }
        XCTAssertEqual(saved.map(\.name), ["C", "B", "A"])
    }

    func test_reordering_singleElement_returnsNil() {
        let only = namedLayout("Only", sortIndex: 3)
        XCTAssertNil(sut.reordering([only], orderedIDs: [only.id]))
    }
}
