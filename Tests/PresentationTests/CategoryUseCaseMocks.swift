import Foundation
@testable import YourUsual

final class MockRegisterCategoryUseCase: AsyncUseCase, @unchecked Sendable {
    var callCount = 0
    var receivedName: String?
    var result = CategoryResponse(id: UUID(), name: "stub", sortIndex: 0)

    func execute(_ request: RegisterCategoryRequest) async throws -> CategoryResponse {
        callCount += 1
        receivedName = request.name
        return result
    }
}

final class MockDeleteCategoryUseCase: AsyncUseCase, @unchecked Sendable {
    var callCount = 0
    var deletedID: UUID?

    func execute(_ request: DeleteCategoryRequest) async throws {
        callCount += 1
        deletedID = request.id
    }
}

final class MockReorderCategoriesUseCase: AsyncUseCase, @unchecked Sendable {
    var callCount = 0
    var orderedIDs: [UUID]?

    func execute(_ request: ReorderCategoriesRequest) async throws {
        callCount += 1
        orderedIDs = request.orderedIDs
    }
}

final class MockEditCategoryUseCase: AsyncUseCase, @unchecked Sendable {
    var callCount = 0
    var received: EditCategoryRequest?

    func execute(_ request: EditCategoryRequest) async throws {
        callCount += 1
        received = request
    }
}
