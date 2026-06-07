import XCTest
@testable import YourUsual

private final class FileSystemRepositoryMock: FileSystemRepositoryProtocol {
    let home: URL
    let validDirectories: Set<String>

    init(home: URL, validDirectories: Set<String>) {
        self.home = home
        self.validDirectories = validDirectories
    }

    func homeDirectory() -> URL { home }
    func isDirectory(_ url: URL) -> Bool { validDirectories.contains(url.path) }
}

final class WorkingDirectoryResolverTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/test")

    private func makeResolver(valid: Set<String>) -> WorkingDirectoryResolver {
        WorkingDirectoryResolver(
            repository: FileSystemRepositoryMock(home: home, validDirectories: valid)
        )
    }

    func testNilPathResolvesToHome() {
        let resolver = makeResolver(valid: [])
        XCTAssertEqual(resolver.resolve(nil), home)
    }

    func testEmptyOrWhitespacePathResolvesToHome() {
        let resolver = makeResolver(valid: [])
        XCTAssertEqual(resolver.resolve(""), home)
        XCTAssertEqual(resolver.resolve("   "), home)
    }

    func testValidDirectoryIsPreserved() {
        let resolver = makeResolver(valid: ["/Users/test/projects"])
        XCTAssertEqual(
            resolver.resolve("/Users/test/projects"),
            URL(fileURLWithPath: "/Users/test/projects")
        )
    }

    func testInvalidDirectoryFallsBackToHome() {
        let resolver = makeResolver(valid: ["/Users/test/projects"])
        XCTAssertEqual(resolver.resolve("/no/such/dir"), home)
    }

    func testValidPathIsTrimmedBeforeResolving() {
        let resolver = makeResolver(valid: ["/Users/test/projects"])
        XCTAssertEqual(
            resolver.resolve("  /Users/test/projects  "),
            URL(fileURLWithPath: "/Users/test/projects")
        )
    }

    func testBareTildeExpandsToHome() {
        let resolver = makeResolver(valid: ["/Users/test"])
        XCTAssertEqual(resolver.resolve("~"), URL(fileURLWithPath: "/Users/test"))
    }

    func testTildeSlashExpandsAgainstHome() {
        let resolver = makeResolver(valid: ["/Users/test/projects"])
        XCTAssertEqual(
            resolver.resolve("~/projects"),
            URL(fileURLWithPath: "/Users/test/projects")
        )
    }

    func testTildePathToInvalidDirectoryFallsBackToHome() {
        let resolver = makeResolver(valid: ["/Users/test/projects"])
        XCTAssertEqual(resolver.resolve("~/nope"), home)
    }

    func testOtherUserTildeIsNotExpandedAndFallsBackToHome() {
        // `~other` is intentionally not expanded; it is not a real directory here, so it
        // resolves to home rather than to some other user's path.
        let resolver = makeResolver(valid: ["/Users/test"])
        XCTAssertEqual(resolver.resolve("~other/projects"), home)
    }
}
