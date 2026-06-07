import XCTest
@testable import YourUsual

// MARK: - Pad service mock

/// Records the `linkedEntryKind` handed to `makePadCell` so the test can assert the use case
/// resolved the linked entry's kind. Reads return test-stubbed collections; the pure
/// transforms return trivial results sufficient for the save flow.
final class MockPadService: PadServiceProtocol, @unchecked Sendable {
    var listAllResult: [PadLayout] = []
    func listAll() async throws -> [PadLayout] { listAllResult }

    func list(forLayout layoutID: UUID) async throws -> [PadCell] { [] }
    func listAllCells() async throws -> [PadCell] { [] }

    func makePadLayout(name: String, columns: Int, rows: Int, sortIndex: Int) -> PadLayout {
        PadLayout(id: UUID(), name: name, columns: columns, rows: rows, sortIndex: sortIndex)
    }
    func updatingPadLayout(_ layout: PadLayout, name: String, columns: Int, rows: Int) -> PadLayout {
        layout.applying(name: name, columns: columns, rows: rows)
    }
    func reordering(_ current: [PadLayout], orderedIDs: [UUID]) -> [PadLayout]? { nil }

    var makePadCellCallCount = 0
    var receivedLinkedEntryKind: EntryKind??
    func makePadCell(
        layoutID: UUID, draft: PadCellDraft, fitting layout: PadLayout, linkedEntryKind: EntryKind?
    ) throws -> PadCell {
        makePadCellCallCount += 1
        receivedLinkedEntryKind = linkedEntryKind
        return PadCell(
            id: UUID(), layoutID: layoutID,
            column: draft.column, row: draft.row,
            columnSpan: draft.columnSpan, rowSpan: draft.rowSpan,
            entryID: draft.entryID,
            backgroundColor: draft.backgroundColor,
            customIconName: draft.customIconName,
            customIconImageName: draft.customIconImageName,
            customLabel: draft.customLabel
        )
    }

    func prunedCells(_ cells: [PadCell], forNewColumns columns: Int, newRows rows: Int) -> [PadCell] { cells }
    func applyingCellChange(_ cells: [PadCell], newCell: PadCell) throws -> [PadCell] { cells + [newCell] }
    func removingCell(at column: Int, row: Int, from cells: [PadCell]) -> [PadCell] { cells }

    func iconsDirectory() async throws -> URL { URL(fileURLWithPath: "/tmp") }
    func probeIconSize(source: URL) async throws -> PixelSize { PixelSize(width: 1, height: 1) }
    func importIcon(source: URL, crop: IconCrop) async throws -> String { "icon.png" }
    func deleteIcon(name: String) async throws {}
}

// MARK: - Tests

final class SavePadCellUseCaseTests: XCTestCase {
    private var sut: SavePadCellUseCase!
    private var mockPad: MockPadService!
    private var mockEntries: MockSavedEntryService!
    private var mockDB: MockDB!
    private let layoutID = UUID()

    override func setUp() {
        super.setUp()
        mockPad = MockPadService()
        mockPad.listAllResult = [PadLayout(id: layoutID, name: "Pad", columns: 4, rows: 4, sortIndex: 0)]
        mockEntries = MockSavedEntryService()
        mockDB = MockDB()
        sut = SavePadCellUseCase(padService: mockPad, entries: mockEntries, db: mockDB)
    }

    override func tearDown() {
        sut = nil
        mockPad = nil
        mockEntries = nil
        mockDB = nil
        super.tearDown()
    }

    private func request(entryID: UUID?) -> SavePadCellRequest {
        SavePadCellRequest(
            layoutID: layoutID, column: 0, row: 0, columnSpan: 2, rowSpan: 1,
            entryID: entryID,
            backgroundColor: nil, customIconName: nil, customLabel: nil,
            sliderOrientation: .horizontal,
            customIconImageName: nil, newIconSourcePath: nil, newIconCrop: nil,
            previousIconImageName: nil
        )
    }

    private func sliderEntry(id: UUID) -> SavedEntry {
        SavedEntry(
            id: id, name: "Volume",
            kind: .slider(SliderEntry(
                commandLine: "v <VALUE>", minValue: 0, maxValue: 100, step: 1, currentValue: 0
            )),
            sortIndex: 0
        )
    }

    // MARK: - Linked entry resolution

    func testExecute_withEntryID_readsEntriesToResolveKind() async throws {
        let entryID = UUID()
        mockEntries.listAllResult = [sliderEntry(id: entryID)]
        try await sut.execute(request(entryID: entryID))
        XCTAssertEqual(mockEntries.listAllCallCount, 1)
    }

    func testExecute_withSliderEntryID_passesResolvedKindToMakePadCell() async throws {
        let entryID = UUID()
        mockEntries.listAllResult = [sliderEntry(id: entryID)]
        try await sut.execute(request(entryID: entryID))
        guard case .some(.some(.slider)) = mockPad.receivedLinkedEntryKind else {
            return XCTFail("Expected the slider kind to be passed to makePadCell")
        }
    }

    func testExecute_withUnknownEntryID_passesNilKind() async throws {
        mockEntries.listAllResult = []
        try await sut.execute(request(entryID: UUID()))
        XCTAssertEqual(mockPad.receivedLinkedEntryKind, .some(nil))
    }

    // MARK: - Unlinked cell (button) — no entry read

    func testExecute_withoutEntryID_doesNotReadEntries() async throws {
        try await sut.execute(request(entryID: nil))
        XCTAssertEqual(mockEntries.listAllCallCount, 0)
    }

    func testExecute_withoutEntryID_passesNilKind() async throws {
        try await sut.execute(request(entryID: nil))
        XCTAssertEqual(mockPad.receivedLinkedEntryKind, .some(nil))
    }

    // MARK: - Commit

    func testExecute_commitsCellsInOneTransaction() async throws {
        try await sut.execute(request(entryID: nil))
        XCTAssertEqual(mockDB.tx.replacePadCellsCallCount, 1)
    }

    // MARK: - Missing layout

    func testExecute_unknownLayout_throwsItemNotFound() async throws {
        mockPad.listAllResult = []
        do {
            try await sut.execute(request(entryID: nil))
            XCTFail("Expected itemNotFound to be thrown")
        } catch {
            XCTAssertEqual(error as? OperationError, .itemNotFound(id: layoutID))
        }
    }
}
