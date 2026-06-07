import Foundation

struct SavedEntryResponse: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let kind: EntryKindPayload     // reused for display + edit-form prefill + click payload
    let categoryID: UUID         // owning category — drives menu grouping
    /// True when this entry is a decode-recovery placeholder (original definition lost).
    /// Presentation badges it and confirms before an edit overwrites the original.
    let isRecovered: Bool
    /// When true, this entry is omitted from the menu bar listing (it remains visible in
    /// the Pad and in Settings). Presentation uses it to filter and to prefill the form.
    let isHiddenFromMenuBar: Bool

    /// Run-and-stream vs. open — the UseCase's routing decision. Fully derived from
    /// `kind` via the single source of truth, so it is computed (never stored): there
    /// is no way to construct an entry whose execution contradicts its kind.
    var execution: ExecutionStyle { .resolve(for: kind) }

    /// Whether activating this entry persists a durable run-history record. Only a
    /// **background command** does: its result outlives the menu that triggered it and
    /// has post-hoc value (exit code, captured output). Terminal commands and browse
    /// entries are fire-and-forget; AppleScript runs stream their result but keep no
    /// history (see `RunStreamingEntryUseCase`). Presentation reads this to decide
    /// whether to surface the per-entry History affordance — it must not re-derive the
    /// rule. Exhaustive `switch` so a new `EntryKind` is a compile error here.
    var recordsRunHistory: Bool {
        switch kind {
        case .command(let command): return command.sink == .background
        case .appleScript, .browse: return false
        case .slider:               return false
        }
    }

    init(
        id: UUID,
        name: String,
        kind: EntryKindPayload,
        categoryID: UUID = EntryCategory.defaultID,
        isRecovered: Bool = false,
        isHiddenFromMenuBar: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.categoryID = categoryID
        self.isRecovered = isRecovered
        self.isHiddenFromMenuBar = isHiddenFromMenuBar
    }
}
