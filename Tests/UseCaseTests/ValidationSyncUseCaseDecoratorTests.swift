import XCTest
@testable import YourUsual

final class ValidationSyncUseCaseDecoratorTests: XCTestCase {

    private struct StubRequest: ValidatableRequest {
        let shouldThrow: Bool
        func validate() throws {
            if shouldThrow { throw OperationError.invalidItem(reason: "stub") }
        }
    }

    private final class SpyUseCase: SyncUseCase, @unchecked Sendable {
        private(set) var executeCallCount = 0
        func execute(_ request: StubRequest) throws -> String {
            executeCallCount += 1
            return "ok"
        }
    }

    func test_execute_validRequest_delegatesToDecoratee() throws {
        let sut = ValidationSyncUseCaseDecorator(decoratee: SpyUseCase())
        XCTAssertEqual(try sut.execute(StubRequest(shouldThrow: false)), "ok")
    }

    func test_execute_validRequest_callsDecorateeOnce() throws {
        let spy = SpyUseCase()
        let sut = ValidationSyncUseCaseDecorator(decoratee: spy)
        _ = try sut.execute(StubRequest(shouldThrow: false))
        XCTAssertEqual(spy.executeCallCount, 1)
    }

    func test_execute_invalidRequest_doesNotCallDecoratee() throws {
        let spy = SpyUseCase()
        let sut = ValidationSyncUseCaseDecorator(decoratee: spy)
        do {
            _ = try sut.execute(StubRequest(shouldThrow: true))
            XCTFail("Expected validation to throw")
        } catch {
            XCTAssertEqual(spy.executeCallCount, 0)
        }
    }

    func test_execute_invalidRequest_propagatesValidationError() throws {
        let sut = ValidationSyncUseCaseDecorator(decoratee: SpyUseCase())
        do {
            _ = try sut.execute(StubRequest(shouldThrow: true))
            XCTFail("Expected validation to throw")
        } catch {
            guard case OperationError.invalidItem = error else {
                return XCTFail("Expected OperationError.invalidItem, got \(error)")
            }
        }
    }
}
