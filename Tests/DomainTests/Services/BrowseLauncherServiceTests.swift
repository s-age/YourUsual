import XCTest
@testable import YourUsual

final class BrowseLauncherServiceTests: XCTestCase {
    private var sut: BrowseLauncherService!
    private var launcher: MockBrowseLauncherRepository!

    override func setUp() {
        super.setUp()
        launcher = MockBrowseLauncherRepository()
        sut = BrowseLauncherService(launcher: launcher)
    }

    override func tearDown() {
        sut = nil
        launcher = nil
        super.tearDown()
    }

    // MARK: - .default app

    func test_launch_defaultApp_callsOpenOnce() async throws {
        let entry = BrowseEntry(url: URL(fileURLWithPath: "/tmp/notes.txt"), app: .default)
        try await sut.launch(entry)
        XCTAssertEqual(launcher.openPathCallCount, 1)
    }

    func test_launch_defaultApp_passesNilBundleID() async throws {
        let entry = BrowseEntry(url: URL(fileURLWithPath: "/tmp/notes.txt"), app: .default)
        try await sut.launch(entry)
        XCTAssertNil(launcher.openedBundleID)
    }

    func test_launch_defaultApp_passesURL() async throws {
        let url = URL(fileURLWithPath: "/tmp/notes.txt")
        try await sut.launch(BrowseEntry(url: url, app: .default))
        XCTAssertEqual(launcher.openedPath, url)
    }

    // MARK: - specific app

    func test_launch_specificApp_callsOpenOnce() async throws {
        let entry = BrowseEntry(
            url: URL(fileURLWithPath: "/tmp/notes.txt"),
            app: .app(bundleIdentifier: "com.apple.TextEdit")
        )
        try await sut.launch(entry)
        XCTAssertEqual(launcher.openPathCallCount, 1)
    }

    func test_launch_specificApp_passesBundleID() async throws {
        let entry = BrowseEntry(
            url: URL(fileURLWithPath: "/tmp/notes.txt"),
            app: .app(bundleIdentifier: "com.apple.TextEdit")
        )
        try await sut.launch(entry)
        XCTAssertEqual(launcher.openedBundleID, "com.apple.TextEdit")
    }
}
