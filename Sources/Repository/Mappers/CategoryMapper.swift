import Foundation

/// Single source of truth for `CategoryDTO` ⇄ `EntryCategory` conversion. Both the
/// write path (`RegistryDatabaseGateway`) and the read path (`CategoryRepository`)
/// route through here so the pair cannot drift apart.
enum CategoryMapper {
    static func toDTO(_ category: EntryCategory) -> CategoryDTO {
        CategoryDTO(
            id: category.id, name: category.name, sortIndex: category.sortIndex,
            isHiddenFromMenuBar: category.isHiddenFromMenuBar
        )
    }

    static func toEntity(_ dto: CategoryDTO) -> EntryCategory {
        EntryCategory(
            id: dto.id, name: dto.name, sortIndex: dto.sortIndex,
            isHiddenFromMenuBar: dto.isHiddenFromMenuBar
        )
    }
}
