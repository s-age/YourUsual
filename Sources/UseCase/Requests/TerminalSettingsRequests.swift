import Foundation

struct ReadTerminalSettingsRequest: UseCaseRequest {}

/// One-shot startup request: rewrite the stored terminal preference to its canonical
/// form (reset if corrupt, or canonicalize a coerced launchMode) so it stops re-warning.
struct NormalizeTerminalPreferenceRequest: UseCaseRequest {}

/// Selects a terminal + launch mode. For `.other` apps, `bundleIdentifier` and
/// `name` carry the browsed app's identity; they are ignored for known kinds.
struct SetTerminalPreferenceRequest: UseCaseRequest {
    let appKind: TerminalAppOptionResponse.Kind
    let bundleIdentifier: String
    let name: String
    let launchMode: TerminalLaunchModeResponse
}

/// Resolves a browsed `.app` URL into a pickable option (or nil if not an app).
struct ResolveTerminalAppRequest: UseCaseRequest {
    let url: URL
}

// MARK: - Request → Domain

extension SetTerminalPreferenceRequest {
    /// Maps the picked app kind (plus the browsed identity for `.other`) to the
    /// domain selection — the Request→Domain conversion the UseCase delegates to.
    var selection: TerminalAppSelection {
        switch appKind {
        case .terminal: return .known(.terminal)
        case .iterm:    return .known(.iterm)
        case .other:    return .other(bundleIdentifier: bundleIdentifier, name: name)
        }
    }
}
