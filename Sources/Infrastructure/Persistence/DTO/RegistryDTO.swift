import Foundation

struct RegistryDTO: Codable, Sendable {
    var items: [RegisteredItemDTO]
}

struct RegisteredItemDTO: Codable, Sendable {
    var id: UUID
    var name: String
    var sortIndex: Int
    var targetKind: String           // "path" | "command" | "applescript"
    var path: String?                // targetKind == path
    var commandLine: String?         // targetKind == command (shell command line)
    var workingDirectory: String?    // targetKind == command (optional)
    var executable: String?          // legacy (pre-shell): read-only fallback
    var arguments: [String]?         // legacy (pre-shell): read-only fallback
    var handlerKind: String          // "defaultApp" | "app" | "background" | "terminal" | "applescript"
    var appBundleIdentifier: String? // handlerKind == app
    var terminal: String?            // handlerKind == terminal: "terminal" | "iterm"
    var applescriptSource: String?   // targetKind == applescript
    var categoryID: UUID? = nil      // owning category; nil = legacy/unassigned → Default
    // Optional-with-default (mirrors `categoryID`) so synthesized `Codable` tolerates the
    // missing key in legacy registry.json blobs written before this field existed — a
    // non-optional `Bool = false` would throw `keyNotFound` on decode. The mapper
    // coalesces `nil → false` (nil = visible).
    var isHiddenFromMenuBar: Bool? = nil
    // targetKind == slider. The command line is reused from `commandLine` (same field as
    // a command entry); only these numeric fields are slider-specific. Optional-with-default
    // for the same Codable back-compat reason as `categoryID`/`isHiddenFromMenuBar`.
    var sliderMinValue: Double? = nil
    var sliderMaxValue: Double? = nil
    var sliderStep: Double? = nil
    var sliderCurrentValue: Double? = nil
}
