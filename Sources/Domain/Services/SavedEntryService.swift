import Foundation

final class SavedEntryService: SavedEntryServiceProtocol, Sendable {
    private let repository: any SavedEntryRepositoryProtocol

    init(repository: any SavedEntryRepositoryProtocol) {
        self.repository = repository
    }

    func listAll() async throws -> [SavedEntry] { try await repository.listAll() }

    /// Domain rule: a slider lives only on the Pad, so it is always hidden from the menu
    /// bar listing regardless of UI input. Pure helper shared by `registering`/`editing`.
    private static func forcesHiddenFromMenuBar(_ kind: EntryKind) -> Bool {
        if case .slider = kind { return true }
        return false
    }

    func healingRecovered(_ current: [SavedEntry]) -> (items: [SavedEntry], healedCount: Int)? {
        // No-op unless at least one entry is a recovery placeholder, so we never rewrite
        // an intact registry. When healing, **clear the flag** on the placeholders: that
        // is what makes the write path persist them (the deliberate conversion) rather
        // than preserve them, and it is a domain decision — it belongs here, not in the
        // UseCase. `healedCount` is returned alongside the collection so "which/how many
        // entries are recovery placeholders" is evaluated **only here** — the UseCase no
        // longer re-applies the `isRecovered` predicate to derive a count.
        let healedCount = current.lazy.filter(\.isRecovered).count
        guard healedCount > 0 else { return nil }
        let items = current.map { entry -> SavedEntry in
            guard entry.isRecovered else { return entry }
            var materialized = entry
            materialized.isRecovered = false
            return materialized
        }
        return (items, healedCount)
    }

    func registering(
        _ current: [SavedEntry], name: String, kind: EntryKind, categoryID: UUID?
    ) -> (items: [SavedEntry], registered: SavedEntry) {
        var items = current
        // Append after all existing entries. sortIndex grows monotonically (slots
        // freed by deletes are not reused) — by design: only relative order matters,
        // reorder() renumbers within the reused slots, and Int overflow is not a
        // practical concern.
        let next = (items.map(\.sortIndex).max() ?? -1) + 1
        // Normalize for storage; non-empty validation runs upstream in the Request.
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Fall back to the Default category when no target category is given.
        let item = SavedEntry(
            name: trimmedName,
            kind: kind,
            sortIndex: next,
            categoryID: categoryID ?? EntryCategory.defaultID,
            // slider → always hidden from the menu bar; any other kind stays visible.
            isHiddenFromMenuBar: Self.forcesHiddenFromMenuBar(kind)
        )
        items.append(item)
        return (items, item)
    }

    func editing(
        _ current: [SavedEntry], id: UUID, edit: SavedEntryEdit
    ) throws -> (items: [SavedEntry], edited: SavedEntry) {
        var items = current
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            throw OperationError.itemNotFound(id: id)
        }
        var updated = items[index]      // preserves id + sortIndex + categoryID
        // Normalize for storage; non-empty validation runs upstream in the Request.
        updated.name = edit.name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.kind = edit.kind
        // slider → force hidden regardless of the UI input; otherwise honour the edit.
        updated.isHiddenFromMenuBar = edit.isHiddenFromMenuBar || Self.forcesHiddenFromMenuBar(edit.kind)
        // The user re-entered a real definition, so this is no longer a recovery
        // placeholder: clear the flag so the write path overwrites the original stored
        // row (the deliberate overwrite the edit-confirmation dialog warned about).
        updated.isRecovered = false
        items[index] = updated
        return (items, updated)
    }

    // Note on recovery placeholders (`isRecovered`): `reordering`/`moving` deliberately
    // do **not** clear the flag (unlike `editing`), so the write path still preserves the
    // undecodable original — a mere reposition must not destroy it. The two transforms
    // differ in *how* they stay safe:
    //   - `moving` is already a clean persistence no-op for a placeholder: it only
    //     re-stamps the moved entry's own slot/category, which the write path discards
    //     (preserve), and it never touches a sibling — so it springs back on reload with
    //     nothing else disturbed.
    //   - `reordering` must additionally **exclude** placeholders from the slot pool
    //     (below). A placeholder's slot is never persisted, so handing it to a sibling
    //     would leave two entries sharing one slot — a non-deterministic reload order.
    //     Excluding it keeps the placeholder put and renumbers only the real entries
    //     among the slots they already own.
    // Either way a placeholder is only truly repositioned once it has been healed (startup)
    // or edited (the user re-entered it). The window is narrow: the startup heal converts
    // placeholders before the UI is interactive, so this only matters between corruption
    // and the next launch — or if that best-effort heal threw and left a placeholder live.
    func reordering(_ current: [SavedEntry], orderedIDs: [UUID]) -> [SavedEntry]? {
        var byID = current.reduce(into: [UUID: SavedEntry]()) { $0[$1.id] = $1 }

        // Only existing, non-placeholder entries are reordered; preserve the caller's order.
        // A recovery placeholder is dropped here so its (unpersisted) slot is not reassigned
        // to a sibling — see the note above.
        let targets = orderedIDs.compactMap { byID[$0] }.filter { !$0.isRecovered }
        guard targets.count > 1 else { return nil }

        // Reuse the sortIndex slots these entries already occupy (kept ascending),
        // so other categories' ordering is left untouched.
        let slots = targets.map(\.sortIndex).sorted()
        for (slot, entry) in zip(slots, targets) {
            byID[entry.id]?.sortIndex = slot
        }

        // Return in ascending sortIndex order. The downstream `replaceAll` reconciles by
        // id (order-independent), but returning the meaningful order — matching
        // `CategoryService.reordering`, which also returns an ordered array — keeps the
        // gerund contract uniform so a reader never has to wonder if the array order means
        // anything.
        return byID.values.sorted { $0.sortIndex < $1.sortIndex }
    }

    func moving(
        _ current: [SavedEntry], id: UUID, toCategory categoryID: UUID,
        knownCategoryIDs: Set<UUID>
    ) throws -> [SavedEntry]? {
        var items = current
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            throw OperationError.itemNotFound(id: id)
        }
        // Reject a move to a category that no longer exists, rather than silently
        // creating an orphan entry (one whose categoryID resolves to nothing). Symmetric
        // with the `itemNotFound` guard above. The caller supplies the known set so this
        // transform stays pure (no category repository).
        guard knownCategoryIDs.contains(categoryID) else {
            throw OperationError.categoryNotFound(id: categoryID)
        }
        guard items[index].categoryID != categoryID else { return nil }
        // Append after the target category's entries by taking the global max
        // slot + 1 (mirrors register), so it lands at the bottom of that list.
        let next = (items.map(\.sortIndex).max() ?? -1) + 1
        items[index].categoryID = categoryID
        items[index].sortIndex = next
        return items
    }

    func deleting(_ current: [SavedEntry], id: UUID) throws -> [SavedEntry] {
        var items = current
        guard items.contains(where: { $0.id == id }) else {
            throw OperationError.itemNotFound(id: id)
        }
        items.removeAll { $0.id == id }
        return items
    }

    func editingSliderValue(_ current: [SavedEntry], id: UUID, value: Double) -> [SavedEntry] {
        // Touch only the matching slider entry; clamp via `SliderEntry.updating`. A
        // missing id or a non-slider match falls through unchanged (no-op) — this is a
        // high-frequency drag-end commit, not a place to throw.
        current.map { entry in
            guard entry.id == id, case .slider(let slider) = entry.kind else { return entry }
            var updated = entry
            updated.kind = .slider(slider.updating(currentValue: value))
            return updated
        }
    }
}
