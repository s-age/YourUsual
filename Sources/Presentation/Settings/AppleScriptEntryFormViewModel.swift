import Foundation
import Observation

/// AppleScript target — owns just the source text.
@Observable
@MainActor
final class AppleScriptEntryFormViewModel {
    var source = ""

    /// Prefill from an existing AppleScript entry when editing.
    func load(_ script: AppleScriptPayload) {
        source = script.source
    }

    func buildKind() -> EntryKindPayload {
        .appleScript(AppleScriptPayload(source: source))
    }
}
