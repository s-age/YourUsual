import Foundation

struct ReadCategoriesRequest: UseCaseRequest {}

struct EnsureDefaultCategoryRequest: UseCaseRequest {}

/// Trimmed-length ceiling for a category name. Measured on the trimmed string so it stays
/// consistent with the emptiness check (which also trims).
private let maxCategoryNameLength = 200

/// Shared name invariant for register/edit — both require a non-blank name within the
/// length ceiling, so the check lives once.
private func validateCategoryName(_ name: String) throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw ValidationError.emptyField(name: "category name")
    }
    guard trimmed.count <= maxCategoryNameLength else {
        throw ValidationError.outOfRange(field: "category name", range: "≤ \(maxCategoryNameLength) characters")
    }
}

struct RegisterCategoryRequest: ValidatableRequest {
    let name: String

    func validate() throws {
        try validateCategoryName(name)
    }
}

struct EditCategoryRequest: ValidatableRequest {
    let id: UUID
    let name: String
    let isHiddenFromMenuBar: Bool

    func validate() throws {
        try validateCategoryName(name)
    }
}

struct DeleteCategoryRequest: UseCaseRequest {
    let id: UUID
}
