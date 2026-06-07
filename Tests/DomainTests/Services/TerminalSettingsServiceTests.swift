import XCTest
@testable import YourUsual

/// Covers the domain classification that `resolveApp` performs: a browsed app's raw
/// identity (from the Repository) is mapped to `.known` when it matches a `TerminalApp`
/// we can drive natively, otherwise `.other`.
final class TerminalSettingsServiceTests: XCTestCase {
    private var repository: MockTerminalSettingsRepository!
    private var sut: TerminalSettingsService!

    override func setUp() {
        super.setUp()
        repository = MockTerminalSettingsRepository()
        sut = TerminalSettingsService(repository: repository)
    }

    override func tearDown() {
        sut = nil
        repository = nil
        super.tearDown()
    }

    func testResolveApp_terminalBundleID_classifiesAsKnownTerminal() {
        repository.resolved = BrowsedApp(
            bundleIdentifier: TerminalApp.terminal.bundleIdentifier, name: "Terminal"
        )
        XCTAssertEqual(sut.resolveApp(at: URL(fileURLWithPath: "/Applications/Terminal.app")),
                       .known(.terminal))
    }

    func testResolveApp_itermBundleID_classifiesAsKnownITerm() {
        repository.resolved = BrowsedApp(
            bundleIdentifier: TerminalApp.iterm.bundleIdentifier, name: "iTerm"
        )
        XCTAssertEqual(sut.resolveApp(at: URL(fileURLWithPath: "/Applications/iTerm.app")),
                       .known(.iterm))
    }

    func testResolveApp_unknownBundleID_classifiesAsOther() {
        repository.resolved = BrowsedApp(bundleIdentifier: "com.example.ghostty", name: "Ghostty")
        XCTAssertEqual(sut.resolveApp(at: URL(fileURLWithPath: "/Applications/Ghostty.app")),
                       .other(bundleIdentifier: "com.example.ghostty", name: "Ghostty"))
    }

    func testResolveApp_notAnApp_returnsNil() {
        repository.resolved = nil
        XCTAssertNil(sut.resolveApp(at: URL(fileURLWithPath: "/tmp/not-an-app")))
    }

    // MARK: - setPreference

    func testSetPreference_supportedMode_returnsAssembledPreference() throws {
        let result = try sut.setPreference(selection: .known(.iterm), launchMode: .newTab)
        XCTAssertEqual(result, TerminalPreference(selection: .known(.iterm), launchMode: .newTab))
    }

    func testSetPreference_unsupportedMode_clampsToSupportedMode() throws {
        // `.other` apps only support `.newWindow`, so `.newTab` is clamped.
        let result = try sut.setPreference(
            selection: .other(bundleIdentifier: "com.example.ghostty", name: "Ghostty"),
            launchMode: .newTab
        )
        XCTAssertEqual(result.launchMode, .newWindow)
    }

    func testSetPreference_persistsConfirmedPreference() throws {
        _ = try sut.setPreference(selection: .known(.terminal), launchMode: .reuse)
        XCTAssertEqual(
            repository.preference,
            TerminalPreference(selection: .known(.terminal), launchMode: .reuse)
        )
    }

    func testSetPreference_callsRepositorySaveOnce() throws {
        _ = try sut.setPreference(selection: .known(.terminal), launchMode: .reuse)
        XCTAssertEqual(repository.savePreferenceCallCount, 1)
    }

    // MARK: - normalizeStoredPreference (delegates to the repository)

    func testNormalizeStoredPreference_delegatesToRepository() throws {
        _ = try sut.normalizeStoredPreference()
        XCTAssertEqual(repository.normalizeStoredPreferenceCallCount, 1)
    }

    func testNormalizeStoredPreference_returnsRepositoryResult() throws {
        repository.normalizeStoredPreferenceResult = true
        XCTAssertTrue(try sut.normalizeStoredPreference())
    }
}
