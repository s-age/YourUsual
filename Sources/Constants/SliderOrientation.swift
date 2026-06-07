import Foundation

// `Constants` is a shared **leaf** layer (Foundation only): it owns cross-layer contract
// vocabulary that more than one layer must agree on. A slider's orientation is persisted as
// a raw string on `SliderEntryModel` (so Infrastructure shares it) and is also referenced by
// Domain (`SliderEntry`), UseCase (`SliderPayload`) and Presentation (the register form / the
// pad cell). Since this single-module codebase has no real module boundaries and Presentation
// may not reference Domain types, the one orientation type lives here — the only home every
// layer can reach (same rationale as `TargetKind`/`HandlerKind`).

/// Whether a slider cell renders as a horizontal or vertical control. `rawValue` is the
/// persisted string; legacy rows without the column decode as `.horizontal`.
enum SliderOrientation: String, CaseIterable, Sendable {
    case horizontal
    case vertical
}
