import XCTest
@testable import YourUsual

final class CurrentDirectoryUseCaseTests: XCTestCase {
    private var service: MockCurrentDirectoryService!
    private var resolver: MockWorkingDirectoryResolver!

    override func setUp() {
        super.setUp()
        service = MockCurrentDirectoryService()
        resolver = MockWorkingDirectoryResolver()
    }

    override func tearDown() {
        service = nil
        resolver = nil
        super.tearDown()
    }

    // MARK: - Read

    func testRead_returnsResolvedPath() throws {
        resolver.resolveResult = URL(fileURLWithPath: "/resolved")
        let sut = ReadCurrentDirectoryUseCase(currentDirectory: service, resolver: resolver)
        let result = try sut.execute(ReadCurrentDirectoryRequest())
        XCTAssertEqual(result.path, "/resolved")
    }

    func testRead_resolvesTheStoredRawPath() throws {
        service.preference = CurrentDirectoryPreference(path: "/raw")
        let sut = ReadCurrentDirectoryUseCase(currentDirectory: service, resolver: resolver)
        _ = try sut.execute(ReadCurrentDirectoryRequest())
        XCTAssertEqual(resolver.resolvedInputs, ["/raw"])
    }

    // MARK: - Set

    func testSet_persistsTheGivenPath() throws {
        let sut = SetCurrentDirectoryUseCase(currentDirectory: service, resolver: resolver)
        _ = try sut.execute(SetCurrentDirectoryRequest(path: "/new"))
        XCTAssertEqual(service.setPathValues, ["/new"])
    }

    func testSet_returnsResolvedPath() throws {
        resolver.resolveResult = URL(fileURLWithPath: "/resolved")
        let sut = SetCurrentDirectoryUseCase(currentDirectory: service, resolver: resolver)
        let result = try sut.execute(SetCurrentDirectoryRequest(path: "/new"))
        XCTAssertEqual(result.path, "/resolved")
    }

    func testSet_propagatesWriteFailure() {
        struct WriteError: Error {}
        service.setPathError = WriteError()
        let sut = SetCurrentDirectoryUseCase(currentDirectory: service, resolver: resolver)
        XCTAssertThrowsError(try sut.execute(SetCurrentDirectoryRequest(path: "/new")))
    }
}
