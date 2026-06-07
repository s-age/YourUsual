import XCTest
@testable import YourUsual

final class CommandOutputSettingsServiceTests: XCTestCase {
    private var repository: MockCommandOutputSettingsRepository!
    private var sut: CommandOutputSettingsService!

    override func setUp() {
        super.setUp()
        repository = MockCommandOutputSettingsRepository()
        sut = CommandOutputSettingsService(repository: repository)
    }

    override func tearDown() {
        sut = nil
        repository = nil
        super.tearDown()
    }

    func testCurrent_returnsRepositoryValue() {
        repository.loadResult = CommandOutputPreference(bufferLines: 2500)
        XCTAssertEqual(sut.current().bufferLines, 2500)
    }

    func testSetBufferLines_persistsClampedValue() {
        _ = sut.setBufferLines(10_000_000)
        XCTAssertEqual(repository.saved?.bufferLines, CommandOutputPreference.maxBufferLines)
    }

    func testSetBufferLines_returnsConfirmedClampedPreference() {
        let result = sut.setBufferLines(1)
        XCTAssertEqual(result.bufferLines, CommandOutputPreference.minBufferLines)
    }
}

private final class MockCommandOutputSettingsRepository:
    CommandOutputSettingsRepositoryProtocol, @unchecked Sendable {
    var loadResult = CommandOutputPreference.default
    var saved: CommandOutputPreference?

    func loadPreference() -> CommandOutputPreference { loadResult }
    func savePreference(_ preference: CommandOutputPreference) { saved = preference }
}
