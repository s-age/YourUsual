import Foundation

// `Constants` is a shared **leaf** layer (depends on `Foundation` only, like `Error`):
// it owns cross-layer contract vocabulary that more than one layer must agree on, so
// the single source of truth lives here instead of being hand-synced between layers.
//
// These are the persisted/transport discriminator strings of a `RegisteredItemDTO`.
// Both the Repository mapper (`RegisteredItemMapper`, DTO ⇄ entity) and the
// Infrastructure store (`RegistryDatabase` EntryStore, @Model ⇄ DTO) read and write
// them; because Infrastructure cannot import Repository, the vocabulary cannot live in
// the mapper. Defining it once here — referenceable from every layer — keeps the
// encode and decode sides from drifting (a drift would silently degrade a registered
// entry into an empty recovered one on read).

/// The `RegisteredItemDTO.targetKind` discriminator. `rawValue` is the persisted string.
enum TargetKind: String {
    case path
    case command
    case applescript
    case slider
}

/// The `RegisteredItemDTO.handlerKind` discriminator. `rawValue` is the persisted string.
/// Spans the browse handlers (`defaultApp`/`app`), the command sinks
/// (`background`/`terminal`), and `applescript`. A slider is always a single
/// background fire-and-forget handler, so it is represented by the lone `slider` value.
enum HandlerKind: String {
    case defaultApp
    case app
    case background
    case terminal
    case applescript
    case slider
}
