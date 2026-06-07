import XCTest
@testable import YourUsual

final class ValidationAsyncUseCaseDecoratorTests: XCTestCase {

    private struct StubRequest: ValidatableRequest {
        let shouldThrow: Bool
        func validate() throws {
            if shouldThrow { throw OperationError.invalidItem(reason: "stub") }
        }
    }

    private final class SpyUseCase: AsyncUseCase, @unchecked Sendable {
        private(set) var executeCallCount = 0
        func execute(_ request: StubRequest) async throws -> String {
            executeCallCount += 1
            return "ok"
        }
    }

    func test_execute_validRequest_delegatesToDecoratee() async throws {
        let spy = SpyUseCase()
        let sut = ValidationAsyncUseCaseDecorator(decoratee: spy)
        let result = try await sut.execute(StubRequest(shouldThrow: false))
        XCTAssertEqual(result, "ok")
    }

    func test_execute_validRequest_callsDecorateeOnce() async throws {
        let spy = SpyUseCase()
        let sut = ValidationAsyncUseCaseDecorator(decoratee: spy)
        _ = try await sut.execute(StubRequest(shouldThrow: false))
        XCTAssertEqual(spy.executeCallCount, 1)
    }

    func test_execute_invalidRequest_doesNotCallDecoratee() async throws {
        let spy = SpyUseCase()
        let sut = ValidationAsyncUseCaseDecorator(decoratee: spy)
        do {
            _ = try await sut.execute(StubRequest(shouldThrow: true))
            XCTFail("Expected validation to throw")
        } catch {
            XCTAssertEqual(spy.executeCallCount, 0)
        }
    }

    func test_execute_invalidRequest_propagatesValidationError() async throws {
        let sut = ValidationAsyncUseCaseDecorator(decoratee: SpyUseCase())
        do {
            _ = try await sut.execute(StubRequest(shouldThrow: true))
            XCTFail("Expected validation to throw")
        } catch {
            guard case OperationError.invalidItem = error else {
                return XCTFail("Expected OperationError.invalidItem, got \(error)")
            }
        }
    }
}
