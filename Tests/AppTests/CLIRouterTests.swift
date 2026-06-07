import XCTest
@testable import YourUsual

final class CLIRouterTests: XCTestCase {
    private var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    // MARK: - resolve (shell `cd`-style)

    func testResolve_nilArgument_returnsHome() {
        XCTAssertEqual(CLIRouter.resolve(nil), home)
    }

    func testResolve_blankArgument_returnsHome() {
        XCTAssertEqual(CLIRouter.resolve("   "), home)
    }

    func testResolve_tildeAlone_expandsToHome() {
        XCTAssertEqual(CLIRouter.resolve("~"), home)
    }

    func testResolve_tildePrefixed_expandsAgainstHome() {
        XCTAssertEqual(CLIRouter.resolve("~/Documents"), home + "/Documents")
    }

    func testResolve_absolutePath_passesThroughStandardized() {
        XCTAssertEqual(CLIRouter.resolve("/tmp/../tmp/work"), "/tmp/work")
    }

    func testResolve_relativePath_resolvedAgainstCwd() {
        let cwd = FileManager.default.currentDirectoryPath
        XCTAssertEqual(CLIRouter.resolve("sub/dir"), cwd + "/sub/dir")
    }

    // MARK: - initSnippet

    func testInitSnippet_zsh() {
        XCTAssertEqual(CLIRouter.initSnippet(shell: "zsh"),
                       #"yu() { cd "$(command your-usual cd "$@")"; }"#)
    }

    func testInitSnippet_bash_matchesZsh() {
        XCTAssertEqual(CLIRouter.initSnippet(shell: "bash"), CLIRouter.initSnippet(shell: "zsh"))
    }

    func testInitSnippet_fish() {
        XCTAssertEqual(CLIRouter.initSnippet(shell: "fish"),
                       "function yu; cd (command your-usual cd $argv); end")
    }

    // MARK: - handle (verb dispatch + store side effect)

    func testHandle_cd_savesResolvedPathAndReturnsTrue() {
        let store = MockCDStore()
        XCTAssertTrue(CLIRouter.handle(["your-usual", "cd", "/tmp/work"], store: store))
        XCTAssertEqual(store.savedPaths, ["/tmp/work"])
    }

    func testHandle_cd_saveFailure_isReportedNotPropagated() {
        // A persist failure must not crash or propagate (it is reported on stderr); the verb is
        // still consumed (returns true) and the save was attempted so the path still prints.
        struct WriteError: Error {}
        let store = MockCDStore()
        store.saveError = WriteError()
        XCTAssertTrue(CLIRouter.handle(["your-usual", "cd", "/tmp/work"], store: store))
        XCTAssertEqual(store.savedPaths, ["/tmp/work"])
    }

    func testHandle_cdNoArgument_savesHome() {
        let store = MockCDStore()
        _ = CLIRouter.handle(["your-usual", "cd"], store: store)
        XCTAssertEqual(store.savedPaths, [home])
    }

    func testHandle_cdPath_readsStoreAndReturnsTrue() {
        let store = MockCDStore()
        store.stored = "/tmp/x"
        XCTAssertTrue(CLIRouter.handle(["your-usual", "cd-path"], store: store))
        XCTAssertEqual(store.loadCount, 1)
    }

    func testHandle_init_returnsTrueWithoutTouchingStore() {
        let store = MockCDStore()
        XCTAssertTrue(CLIRouter.handle(["your-usual", "init", "zsh"], store: store))
        XCTAssertTrue(store.savedPaths.isEmpty)
        XCTAssertEqual(store.loadCount, 0)
    }

    func testHandle_unknownVerb_returnsFalse() {
        XCTAssertFalse(CLIRouter.handle(["your-usual", "bogus"], store: MockCDStore()))
    }

    func testHandle_noVerb_returnsFalse() {
        XCTAssertFalse(CLIRouter.handle(["your-usual"], store: MockCDStore()))
    }
}

private final class MockCDStore: CurrentDirectoryStoreProtocol, @unchecked Sendable {
    var stored = "/Users/test"
    var loadCount = 0
    var savedPaths: [String?] = []
    var saveError: Error?

    func loadPath() -> String { loadCount += 1; return stored }
    func savePath(_ path: String?) throws {
        savedPaths.append(path)
        if let saveError { throw saveError }
    }
}
