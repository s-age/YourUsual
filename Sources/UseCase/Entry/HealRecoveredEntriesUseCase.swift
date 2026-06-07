import Foundation

/// One-shot startup heal: a registered record that can no longer be decoded (e.g. an
/// upgrade dropped/renamed a discriminator it used) is read back as an empty
/// File/Directory placeholder, flagged `isRecovered`.
///
/// While that flag stays set the placeholder is **lossless**: the write path preserves the
/// still-intact original row (`stageReplaceAllEntries` skips `preservingIDs`), so reordering,
/// moving, and edits to *other* entries leave the original untouched and it simply
/// re-recovers on the next load. Only two paths clear the flag and thus overwrite the
/// original: the user editing this very entry (a deliberate re-entry), and this heal.
///
/// So this heal is a **deliberate trade-off, not a rescue from imminent loss**: left alone,
/// a placeholder would persist losslessly and keep warning forever. The heal instead clears
/// the flag on every placeholder once at startup so they stop re-warning, persists them as
/// the empty shape, and returns how many were reset for the boot layer to surface. The cost
/// is that the original blob is discarded — a *future* version that re-adds the missing
/// discriminator could no longer decode it. We accept that to avoid a permanent warning
/// state the user cannot clear without editing each entry by hand.
final class HealRecoveredEntriesUseCase: AsyncUseCase, Sendable {
    private let entries: any SavedEntryServiceProtocol
    private let db: any DBProtocol

    init(entries: any SavedEntryServiceProtocol, db: any DBProtocol) {
        self.entries = entries
        self.db = db
    }

    func execute(_ request: HealRecoveredEntriesRequest) async throws -> Int {
        let current = try await entries.listAll()
        // The Service decides both the healed collection and how many placeholders it reset;
        // the UseCase only orchestrates read → transform → commit and surfaces the count it
        // is handed. The `isRecovered` predicate is never re-evaluated here.
        guard let healed = entries.healingRecovered(current) else { return 0 }
        try await db.transaction { tx in try tx.replaceAllEntries(healed.items) }
        return healed.healedCount
    }
}
