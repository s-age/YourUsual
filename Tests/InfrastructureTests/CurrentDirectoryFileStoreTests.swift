import XCTest
@testable import YourUsual

final class CurrentDirectoryFileStoreTests: XCTestCase {
    private var fileURL: URL!
    private var sut: CurrentDirectoryFileStore!

    private var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    override func setUp() {
        super.setUp()
        // A temp path (with a non-existent parent dir) so the real Application Support state is
        // never touched and `write` must create intermediate directories.
        fileURL = FileManager.default.temporaryDirectory
            .appending(path: "yu-cd-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "current-directory", directoryHint: .notDirectory)
        sut = CurrentDirectoryFileStore(fileURL: fileURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        sut = nil
        fileURL = nil
        super.tearDown()
    }

    // MARK: - load (tolerant + self-healing)

    func testLoad_missingFile_returnsHome() {
        XCTAssertEqual(sut.loadPath(), home)
    }

    func testLoad_missingFile_selfHealsByWritingDefault() {
        _ = sut.loadPath()
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let written = (try? String(contentsOf: fileURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(written, home)
    }

    func testLoad_emptyFile_returnsHomeAndRewritesDefault() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "   \n".write(to: fileURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(sut.loadPath(), home)
        let written = try String(contentsOf: fileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(written, home)
    }

    // MARK: - save / round-trip

    func testSaveThenLoad_roundTripsAbsolutePath() throws {
        try sut.savePath("/tmp/work")
        XCTAssertEqual(sut.loadPath(), "/tmp/work")
    }

    func testSave_createsIntermediateDirectories() throws {
        try sut.savePath("/tmp/work")   // parent dir did not exist in setUp
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testSave_nil_resetsToHome() throws {
        try sut.savePath("/tmp/work")
        try sut.savePath(nil)
        XCTAssertEqual(sut.loadPath(), home)
    }

    func testSave_blank_resetsToHome() throws {
        try sut.savePath("/tmp/work")
        try sut.savePath("   ")
        XCTAssertEqual(sut.loadPath(), home)
    }

    // MARK: - delete recovery

    func testDeletedFile_recreatesInitialStateOnNextAccess() throws {
        try sut.savePath("/tmp/work")
        try FileManager.default.removeItem(at: fileURL)
        XCTAssertEqual(sut.loadPath(), home)                       // recovers to default
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))  // and rewrites it
    }
}
