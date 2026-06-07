import Foundation

/// Snapshot of the global terminal setting for the settings pane: the pickable
/// terminals, the current selection, and the chosen launch mode.
struct TerminalSettingsResponse: Sendable, Equatable {
    let available: [TerminalAppOptionResponse]
    let selected: TerminalAppOptionResponse
    let launchMode: TerminalLaunchModeResponse
}

/// A pickable terminal. `id` is the bundle identifier (stable Picker tag);
/// `supportedModes` drives which launch-mode controls the UI enables.
struct TerminalAppOptionResponse: Sendable, Equatable, Identifiable {
    enum Kind: String, Sendable, Equatable { case terminal, iterm, other }

    let id: String
    let name: String
    let kind: Kind
    let supportedModes: [TerminalLaunchModeResponse]
}

enum TerminalLaunchModeResponse: String, Sendable, Equatable, CaseIterable, Identifiable {
    case newWindow
    case newTab
    case reuse

    var id: String { rawValue }
}

// MARK: - Entity → Response

extension TerminalSettingsResponse {
    /// Builds the snapshot, guaranteeing `available` contains `selected` (e.g. a
    /// browsed "other" app that is not part of the known-terminal list).
    init(preference: TerminalPreference, available: [TerminalAppSelection]) {
        var options = available.map(TerminalAppOptionResponse.init(from:))
        let selected = TerminalAppOptionResponse(from: preference.selection)
        if !options.contains(where: { $0.id == selected.id }) {
            options.append(selected)
        }
        self.init(
            available: options,
            selected: selected,
            launchMode: TerminalLaunchModeResponse(from: preference.launchMode)
        )
    }
}

extension TerminalAppOptionResponse {
    init(from selection: TerminalAppSelection) {
        let kind: Kind
        let name: String
        switch selection {
        case .known(.terminal): kind = .terminal; name = "Terminal"
        case .known(.iterm):    kind = .iterm;    name = "iTerm2"
        case .other(_, let appName): kind = .other; name = appName
        }
        self.init(
            id: selection.bundleIdentifier,
            name: name,
            kind: kind,
            supportedModes: selection.supportedModes.map(TerminalLaunchModeResponse.init(from:))
        )
    }
}

extension TerminalLaunchModeResponse {
    init(from mode: TerminalLaunchMode) {
        switch mode {
        case .newWindow: self = .newWindow
        case .newTab:    self = .newTab
        case .reuse:     self = .reuse
        }
    }

    var toDomain: TerminalLaunchMode {
        switch self {
        case .newWindow: return .newWindow
        case .newTab:    return .newTab
        case .reuse:     return .reuse
        }
    }
}
