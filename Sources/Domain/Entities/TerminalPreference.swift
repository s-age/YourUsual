import Foundation

/// The global "Terminal App" setting: which terminal to run commands in, and how.
///
/// Construction clamps `launchMode` to one the selected app actually supports, so an
/// invalid (app, mode) pair can never exist — e.g. switching to Terminal.app while
/// `.newTab` was chosen falls back to a supported mode.
struct TerminalPreference: Equatable, Sendable {
    let selection: TerminalAppSelection
    let launchMode: TerminalLaunchMode

    init(selection: TerminalAppSelection, launchMode: TerminalLaunchMode) {
        self.selection = selection
        let supported = selection.supportedModes
        self.launchMode = supported.contains(launchMode)
            ? launchMode
            : (supported.first ?? .newWindow)
    }

    static let `default` = TerminalPreference(
        selection: .known(.terminal),
        launchMode: .newWindow
    )
}
