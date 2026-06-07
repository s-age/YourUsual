import Foundation

/// How a registered entry behaves when activated — a business routing decision
/// owned by the UseCase layer (not re-derived by Presentation).
enum ExecutionStyle: Equatable, Sendable {
    /// Runs on activation and streams output into the result window:
    /// background commands and AppleScript entries.
    case runAndStream
    /// Simply opens the target: browse entries and terminal commands.
    case open
    /// A slider: not a tap activation but a continuous value run (drag-driven, throttled).
    case adjust

    /// Single source of truth for the run-and-stream vs. open routing rule, and the one
    /// that actually drives dispatch (`MenuBarRootView` selects the use case from
    /// `execution`). Expressed as an **exhaustive** `switch` so a newly added `EntryKind`
    /// is a compile error here — it must make an explicit routing decision rather than
    /// silently defaulting to `.open` and mis-dispatching.
    static func resolve(for kind: EntryKindPayload) -> ExecutionStyle {
        switch kind {
        case .command(let command): return command.sink == .background ? .runAndStream : .open
        case .appleScript:          return .runAndStream
        case .browse:               return .open
        case .slider:               return .adjust
        }
    }
}
