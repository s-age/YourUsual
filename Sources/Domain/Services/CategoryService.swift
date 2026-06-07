import Foundation

final class CategoryService: CategoryServiceProtocol, Sendable {
    private let repository: any CategoryRepositoryProtocol

    init(repository: any CategoryRepositoryProtocol) {
        self.repository = repository
    }

    func listAll() async throws -> [EntryCategory] { try await repository.listAll() }

    func ensuringDefault(_ current: [EntryCategory]) -> [EntryCategory]? {
        // Default is the empty-state seed, not an immortal category: it is created
        // only when there are no categories at all. Once the user has any category,
        // deleting Default does not resurrect it.
        guard current.isEmpty else { return nil }
        return [EntryCategory.makeDefault()]
    }

    func registering(
        _ current: [EntryCategory], name: String
    ) -> (categories: [EntryCategory], registered: EntryCategory) {
        // Normalize for storage; non-empty validation runs upstream in the Request.
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var categories = current
        let next = (categories.map(\.sortIndex).max() ?? -1) + 1
        let category = EntryCategory(name: trimmed, sortIndex: next)
        categories.append(category)
        return (categories, category)
    }

    func reordering(_ current: [EntryCategory], orderedIDs: [UUID]) -> [EntryCategory]? {
        // Build with `reduce(into:)`, not `Dictionary(uniqueKeysWithValues:)`: the latter
        // traps on a duplicate id, and a corrupt/legacy store could carry one. This only
        // guarantees we don't crash on such a store — the dedup is not exhaustive here (an
        // unmentioned duplicate is re-appended from `current` below), but a duplicate id is
        // an already-broken-store edge case, so "don't trap" is the bar.
        let byID = current.reduce(into: [UUID: EntryCategory]()) { $0[$1.id] = $1 }
        let ordered = orderedIDs.compactMap { byID[$0] }
        guard ordered.count > 1 else { return nil }
        // Keep any categories the caller didn't mention at the end, in their
        // current order, then renumber the whole list 0..n.
        let mentioned = Set(orderedIDs)
        var result = ordered + current.filter { !mentioned.contains($0.id) }
        for index in result.indices {
            result[index].sortIndex = index
        }
        return result
    }

    func editing(
        _ current: [EntryCategory],
        id: UUID,
        name: String,
        isHiddenFromMenuBar: Bool
    ) throws -> [EntryCategory] {
        guard let index = current.firstIndex(where: { $0.id == id }) else {
            throw OperationError.itemNotFound(id: id)
        }
        // Normalize for storage; non-empty validation runs upstream in the Request.
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var categories = current
        categories[index].name = trimmed
        categories[index].isHiddenFromMenuBar = isHiddenFromMenuBar
        return categories            // preserves id + sortIndex
    }

    func deleting(_ current: [EntryCategory], id: UUID) throws -> [EntryCategory] {
        var categories = current
        // Mirror `SavedEntryService.deleting`: throw on a missing id rather than silently
        // removing nothing, so a stale/out-of-sync delete surfaces instead of being swallowed.
        guard categories.contains(where: { $0.id == id }) else {
            throw OperationError.itemNotFound(id: id)
        }
        categories.removeAll { $0.id == id }
        return categories
    }
}
