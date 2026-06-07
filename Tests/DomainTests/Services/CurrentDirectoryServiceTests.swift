import XCTest
@testable import YourUsual

final class CurrentDirectoryServiceTests: XCTestCase {
    private var repository: MockCurrentDirectoryRepository!
    private var sut: CurrentDirectoryService!

    override func setUp() {
        super.setUp()
        // Mock at the repository boundary — the real store is file-backed (persisted) and
        // must not be touched by a unit test.
        repository = MockCurrentDirectoryRepository()
        sut = CurrentDirectoryService(repository: repository)
    }

    override func tearDown() {
        sut = nil
        repository = nil
        super.tearDown()
    }

    func testCurrent_returnsRepositoryValue() {
        repository.preference = CurrentDirectoryPreference(path: "/tmp/work")
        XCTAssertEqual(sut.current().path, "/tmp/work")
        XCTAssertEqual(repository.loadCallCount, 1)
    }

    func testSetPath_savesTheValue() throws {
        try sut.setPath("/tmp/work")
        XCTAssertEqual(repository.savedPreferences.map(\.path), ["/tmp/work"])
    }

    func testSetPath_trimsSurroundingWhitespace() throws {
        try sut.setPath("  /tmp/work  ")
        XCTAssertEqual(repository.savedPreferences.last?.path, "/tmp/work")
    }

    func testSetPath_blankInputSavesUnset() throws {
        try sut.setPath("   ")
        XCTAssertNil(repository.savedPreferences.last?.path)   // blank → nil (store maps nil → home)
    }

    func testSetPath_propagatesStoreWriteFailure() {
        struct WriteError: Error {}
        repository.saveError = WriteError()
        XCTAssertThrowsError(try sut.setPath("/tmp/work"))
    }
}
