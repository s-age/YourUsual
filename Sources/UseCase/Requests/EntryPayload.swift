import Foundation

// UseCase-layer DTOs describing an entry's kind and its parts. Deliberately named
// `*Payload` (not `*Input`): the same types are reused **bidirectionally** — as input
// on `RegisterEntryRequest`/`EditEntryRequest` and as output on `SavedEntryResponse` —
// so an "Input" suffix would lie about direction wherever a Response carries one. They
// mirror the `Domain/Entities` `EntryKind`/`BrowseEntry`/… types; `EntryMapping`
// converts both ways (`toDomain` / `toPayload`).

enum AppChoicePayload: Equatable, Sendable {
    case `default`
    case app(bundleIdentifier: String)
}

enum CommandSinkPayload: Equatable, Sendable {
    case background
    case terminal
}

struct BrowsePayload: Equatable, Sendable {
    var path: String
    var app: AppChoicePayload
}

struct CommandPayload: Equatable, Sendable {
    var commandLine: String
    var workingDirectory: String?
    var sink: CommandSinkPayload
}

struct AppleScriptPayload: Equatable, Sendable {
    var source: String
}

struct SliderPayload: Equatable, Sendable {
    var commandLine: String
    var minValue: Double
    var maxValue: Double
    var step: Double
    var currentValue: Double
}

enum EntryKindPayload: Equatable, Sendable {
    case browse(BrowsePayload)
    case command(CommandPayload)
    case appleScript(AppleScriptPayload)
    case slider(SliderPayload)
}
