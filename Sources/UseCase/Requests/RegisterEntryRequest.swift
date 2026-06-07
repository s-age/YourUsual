import Foundation

/// Trimmed-length ceilings for entry input fields. Measured on the trimmed string so they
/// stay consistent with the emptiness checks (which also trim).
private enum EntryFieldLimits {
    static let maxNameLength = 200
    static let maxPathLength = 1024
    static let maxCommandLength = 1000
    static let maxAppleScriptLength = 10000
}

/// Trims `value` and asserts it is non-empty and within `maxLength` characters, throwing the
/// matching `ValidationError` for `field`. Length is measured on the trimmed string so it stays
/// consistent with the emptiness check. The name spells out both checks (non-empty *and* the
/// length ceiling) so the call sites don't read as empty-only.
private func requireNonEmptyWithinLimit(_ value: String, field: String, maxLength: Int) throws {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw ValidationError.emptyField(name: field)
    }
    guard trimmed.count <= maxLength else {
        throw ValidationError.outOfRange(field: field, range: "≤ \(maxLength) characters")
    }
}

/// Shared field invariant for registering or editing an entry: a non-empty name and a
/// non-empty, length-bounded target for the kind. Both `RegisterEntryRequest` and
/// `EditEntryRequest` enforce exactly this — extracted to a named check so the *shared*
/// invariant is explicit, rather than `EditEntryRequest` borrowing it by constructing a
/// throwaway `RegisterEntryRequest`. (Register-only invariants, if any are ever added, stay on
/// `RegisterEntryRequest.validate`.)
private func validateEntryFields(name: String, kind: EntryKindPayload) throws {
    try requireNonEmptyWithinLimit(name, field: "name", maxLength: EntryFieldLimits.maxNameLength)
    switch kind {
    case .browse(let browse):
        try requireNonEmptyWithinLimit(browse.path, field: "path", maxLength: EntryFieldLimits.maxPathLength)
    case .command(let command):
        try requireNonEmptyWithinLimit(
            command.commandLine, field: "command", maxLength: EntryFieldLimits.maxCommandLength)
    case .appleScript(let script):
        try requireNonEmptyWithinLimit(
            script.source, field: "AppleScript source", maxLength: EntryFieldLimits.maxAppleScriptLength)
    case .slider(let slider):
        try requireNonEmptyWithinLimit(
            slider.commandLine, field: "Command", maxLength: EntryFieldLimits.maxCommandLength)
        guard slider.commandLine.contains(SliderValueToken.placeholder) else {
            throw ValidationError.invalidFormat(
                field: "Command", reason: "must contain \(SliderValueToken.placeholder)"
            )
        }
        guard slider.minValue < slider.maxValue else {
            throw ValidationError.outOfRange(field: "Range", range: "min < max")
        }
        guard slider.step > 0 else {
            throw ValidationError.outOfRange(field: "Step", range: "> 0")
        }
    }
}

struct RegisterEntryRequest: ValidatableRequest {
    let name: String
    let kind: EntryKindPayload
    /// Target category for the new entry; nil falls back to the Default category.
    let categoryID: UUID?

    init(name: String, kind: EntryKindPayload, categoryID: UUID? = nil) {
        self.name = name
        self.kind = kind
        self.categoryID = categoryID
    }

    func validate() throws {
        try validateEntryFields(name: name, kind: kind)
    }
}

struct EditEntryRequest: ValidatableRequest {
    let id: UUID
    let name: String
    let kind: EntryKindPayload
    /// Whether the edited entry is hidden from the menu bar. **No default** — every
    /// caller must state it, so an edit can never silently un-hide an entry by omitting
    /// it. The form supplies the real value; tests pass it explicitly.
    let isHiddenFromMenuBar: Bool

    init(id: UUID, name: String, kind: EntryKindPayload, isHiddenFromMenuBar: Bool) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isHiddenFromMenuBar = isHiddenFromMenuBar
    }

    func validate() throws {
        try validateEntryFields(name: name, kind: kind)
    }
}

struct DeleteEntryRequest: UseCaseRequest {
    let id: UUID
}

struct ReadEntriesRequest: UseCaseRequest {}

/// One-shot startup request: persist any decode-recovery placeholders so the store
/// is consistent, returning how many entries were reset (for a user-facing notice).
struct HealRecoveredEntriesRequest: UseCaseRequest {}

