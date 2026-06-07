import Foundation
import SwiftData

// CategoryStore lives in its own extension to keep the actor body within the
// type-length budget. `modelContext` is provided by `@ModelActor` on the main
// declaration and is reachable from this same-module extension.
extension RegistryDatabase: CategoryStoreProtocol {

    // Ordering is the store's responsibility (sorted by `sortIndex`), mirroring
    // `fetchAllEntries()`/`fetchAllRuns()` — the repository trusts this order.
    func fetchAllCategories() throws -> [CategoryDTO] {
        try modelContext.fetch(
            FetchDescriptor<CategoryModel>(sortBy: [SortDescriptor(\.sortIndex)])
        ).map(Self.toDTO)
    }

    // MARK: - @Model ↔ DTO (private — @Model must never escape the actor)

    private static func toDTO(_ m: CategoryModel) -> CategoryDTO {
        CategoryDTO(
            id: m.id, name: m.name, sortIndex: m.sortIndex,
            isHiddenFromMenuBar: m.isHiddenFromMenuBar
        )
    }

    static func makeCategoryModel(_ dto: CategoryDTO) -> CategoryModel {
        CategoryModel(
            id: dto.id, name: dto.name, sortIndex: dto.sortIndex,
            isHiddenFromMenuBar: dto.isHiddenFromMenuBar
        )
    }

    static func applyCategoryDTO(_ dto: CategoryDTO, to m: CategoryModel) {
        m.name = dto.name
        m.sortIndex = dto.sortIndex
        m.isHiddenFromMenuBar = dto.isHiddenFromMenuBar
    }
}
