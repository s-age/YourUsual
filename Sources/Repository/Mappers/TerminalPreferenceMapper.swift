import Foundation

/// Single source of truth for `TerminalPreferenceDTO` ⇄ `TerminalPreference`
/// conversion, **including the persisted selection discriminator**. Mirrors
/// `RegisteredItemMapper` / `CategoryMapper` / `RunRecordMapper`: the encode side, the
/// decode side, and the discriminator strings live together so they cannot drift.
///
/// Unlike those three, this concept is read/written entirely within a single
/// DataSource repository (`TerminalSettingsRepository`) rather than across a
/// transaction gateway — but it is extracted anyway so "where is the mapping for a
/// persisted concept?" has one uniform answer across all four. The Repository keeps the
/// *recovery decision* (whether to reset on a decode failure); this only converts.
enum TerminalPreferenceMapper {
    /// `TerminalPreferenceDTO.kind` discriminator values. A single-layer identifier
    /// contract (Infrastructure never branches on it), so it stays here rather than
    /// moving to `Constants` — but expressed as an enum, not raw literals, so the
    /// "this is a persisted discriminator" intent is self-evident (mirrors
    /// `RunRecordMapper.OutcomeKind`).
    private enum SelectionKind {
        static let known = "known"
        static let other = "other"
    }

    // MARK: - Entity → DTO

    static func toDTO(_ preference: TerminalPreference) -> TerminalPreferenceDTO {
        switch preference.selection {
        case .known(let app):
            return TerminalPreferenceDTO(kind: SelectionKind.known, app: app.rawValue,
                                         bundleIdentifier: nil, name: nil,
                                         launchMode: preference.launchMode.rawValue)
        case .other(let id, let name):
            return TerminalPreferenceDTO(kind: SelectionKind.other, app: nil,
                                         bundleIdentifier: id, name: name,
                                         launchMode: preference.launchMode.rawValue)
        }
    }

    // MARK: - DTO → Entity

    /// Decoded preference plus the launchMode-coercion signal the caller logs. The mapper
    /// is a pure enum (no injected logger), so it *reports* the coercion and the
    /// Repository (which holds the logger) observes it.
    struct Decoded {
        let preference: TerminalPreference
        /// The raw `launchMode` string that was **present but unparseable** and got
        /// defaulted — non-nil only in that case, so the Repository can log it. A
        /// *missing* launchMode (`nil`) is expected schema evolution (old blob) and is
        /// reported as `nil` here: defaulting it is normal, not worth a warning.
        let unparsedLaunchMode: String?
    }

    /// Decodes a stored preference. Throws `OperationError.persistenceFailed` with a
    /// reason that names the **specific** breakage (unknown kind / which field is
    /// missing for the declared kind), so a recovery log can distinguish causes —
    /// matching `RunRecordMapper.toEntity`. The caller decides whether to reset.
    static func toEntity(_ dto: TerminalPreferenceDTO) throws -> Decoded {
        // Deliberate asymmetry vs. the `selection` decode below: a missing or unknown
        // `launchMode` falls back to `.default` instead of throwing. `launchMode` is a
        // secondary attribute with a sane default, so coercing it loses nothing — whereas
        // throwing would make the caller discard the *entire* (otherwise valid) selection.
        // "Keep the selection, default just the mode" is the better recovery. It is still
        // observable: a present-but-unparseable value is reported via `unparsedLaunchMode`
        // for the Repository to log (a missing value is normal schema evolution — silent).
        let mode: TerminalLaunchMode
        let unparsedLaunchMode: String?
        switch dto.launchMode {
        case let raw? where TerminalLaunchMode(rawValue: raw) != nil:
            mode = TerminalLaunchMode(rawValue: raw)!
            unparsedLaunchMode = nil
        case let raw?:
            mode = .default
            unparsedLaunchMode = raw          // present but unknown → observable
        case nil:
            mode = .default
            unparsedLaunchMode = nil          // absent → schema evolution, silent
        }

        let selection: TerminalAppSelection
        switch dto.kind {
        case SelectionKind.known:
            guard let raw = dto.app, let app = TerminalApp(rawValue: raw) else {
                throw OperationError.persistenceFailed(
                    reason: "known terminal selection has missing/unknown app (app=\(dto.app ?? "nil"))"
                )
            }
            selection = .known(app)
        case SelectionKind.other:
            guard let id = dto.bundleIdentifier else {
                throw OperationError.persistenceFailed(
                    reason: "other terminal selection is missing bundleIdentifier"
                )
            }
            guard let name = dto.name else {
                throw OperationError.persistenceFailed(
                    reason: "other terminal selection is missing name"
                )
            }
            selection = .other(bundleIdentifier: id, name: name)
        default:
            throw OperationError.persistenceFailed(reason: "unknown terminal selection kind: \(dto.kind)")
        }
        return Decoded(
            preference: TerminalPreference(selection: selection, launchMode: mode),
            unparsedLaunchMode: unparsedLaunchMode
        )
    }
}
