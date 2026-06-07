import Foundation
import Observation

/// Single shared owner of the registry read-model in Presentation. Both the menu
/// bar and settings ViewModels are injected with one instance, so the registry
/// lives in exactly one place; @Observable observation propagates changes across
/// scenes (no manual revision counter). Mutating VMs call `load()` after a
/// successful write to reconcile against the store (the source of truth).
@Observable
@MainActor
final class RegistryViewModel {
    private(set) var items: [SavedEntryResponse] = []
    private(set) var categories: [CategoryResponse] = []

    private let readEntries: ReadEntriesUseCaseProtocol
    private let readCategories: ReadCategoriesUseCaseProtocol

    init(readEntries: ReadEntriesUseCaseProtocol, readCategories: ReadCategoriesUseCaseProtocol) {
        self.readEntries = readEntries
        self.readCategories = readCategories
    }

    /// Reads both lists, assigning only after BOTH succeed so a failure preserves
    /// the last-known-good cache. Rethrows so the caller can surface it (a blanked
    /// list would look like an empty registry). `categories` is kept in sortIndex order.
    func load() async throws {
        let loadedItems = try await readEntries.execute(ReadEntriesRequest())
        let loadedCategories = try await readCategories.execute(ReadCategoriesRequest())
            .sorted { $0.sortIndex < $1.sortIndex }
        items = loadedItems
        categories = loadedCategories
    }

    /// Optimistic write-back from a mutating VM: reflect a reorder/move locally so
    /// the row settles before the persisted `load()` arrives. Order is taken as-is
    /// (NOT re-sorted) — the caller already computed the intended order.
    func applyOptimistic(items: [SavedEntryResponse]) { self.items = items }
    func applyOptimistic(categories: [CategoryResponse]) { self.categories = categories }
}
