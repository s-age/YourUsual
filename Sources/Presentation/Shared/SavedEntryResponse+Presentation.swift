import Foundation

extension SavedEntryResponse {
    /// The category this entry effectively belongs to for display grouping: its own
    /// `categoryID` when that category still exists (`known`), otherwise `fallback`.
    /// Orphan entries — whose owning category was removed — fold into the fallback
    /// category. Both the menu-bar grouping (`MenuItemsViewModel`) and the settings
    /// detail list (`SettingsViewModel`) route orphans through this one rule, so the
    /// fold decision lives in a single place rather than being re-implemented per VM.
    func effectiveCategoryID(known: Set<UUID>, fallback: UUID) -> UUID {
        known.contains(categoryID) ? categoryID : fallback
    }

    /// A copy reassigned to `categoryID`, preserving every other field — notably
    /// `isRecovered`, so an optimistic category move (drag-to-category) does not drop
    /// the recovery badge until the registry reload arrives. Enumerating fields by hand
    /// at the call site risks silently dropping one as the type grows; this keeps the
    /// copy total.
    func withCategory(_ categoryID: UUID) -> Self {
        SavedEntryResponse(
            id: id, name: name, kind: kind, categoryID: categoryID, isRecovered: isRecovered
        )
    }
}
