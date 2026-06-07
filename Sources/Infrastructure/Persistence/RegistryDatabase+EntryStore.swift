import Foundation
import os
import SwiftData

// EntryStore lives in its own extension to keep the actor body within the
// type-length budget. `modelContext` is provided by `@ModelActor` on the main
// declaration and is reachable from this same-module extension.
extension RegistryDatabase: EntryStoreProtocol {

    private static let log = Logger(subsystem: "com.yourusual.app", category: "RegistryDatabase.EntryStore")

    /// The entry's kind, decoded **once** at the boundary so the rest of the store
    /// switches on a compiler-checked enum instead of bare strings. Two vocabularies
    /// meet here: the shared transport `TargetKind` (`Constants`, also used by the
    /// Repository mapper) and the infra-local `entryType` mirror (`"browse"`/`"command"`/
    /// `"applescript"`, this enum's `rawValue`). `TargetKind.path` ↔ `.browse` is the one
    /// non-identity mapping, isolated to `init(targetKind:)` so it can't be mis-typed.
    private enum Kind: String {
        case browse, command, applescript, slider

        /// Decodes the DTO's transport `targetKind` via the shared `TargetKind` enum.
        /// Returns nil for an unknown value — unreachable in practice (the typed domain
        /// enum constrains the mapper output), so callers treat nil as an upstream-mapper
        /// bug: they log it rather than fail the whole batch (see `makeModel`/`apply`).
        init?(targetKind raw: String) {
            switch TargetKind(rawValue: raw) {
            case .path: self = .browse
            case .command: self = .command
            case .applescript: self = .applescript
            case .slider: self = .slider
            case nil: return nil
            }
        }

        /// The kind encoded by **which payload relationship is non-nil** — the single
        /// source of truth for an entry's kind (what `toDTO` reads, what `apply` trusts).
        /// This is the *one* place the browse → command → applescript → slider scan order
        /// lives. Nil when no payload is set yet (a freshly-created or just-cleared model).
        init?(payloadOf m: EntryModel) {
            if m.browse != nil { self = .browse }
            else if m.command != nil { self = .command }
            else if m.applescript != nil { self = .applescript }
            else if m.slider != nil { self = .slider }
            else { return nil }
        }
    }

    // Returns a `RegistryDTO` with empty `items` when the store has none — consistent
    // with the sibling `fetchAllCategories()`/`fetchAllRuns()` (which return `[]`).
    // Ordering is the **store's** responsibility (sorted by `sortIndex`), mirroring the
    // run-history `executedAt` sort — the repository trusts this order rather than
    // re-sorting, so the contract has one home.
    func fetchAllEntries() throws -> RegistryDTO {
        let models = try modelContext.fetch(
            FetchDescriptor<EntryModel>(sortBy: [SortDescriptor(\.sortIndex)])
        )
        return RegistryDTO(items: models.map(Self.toDTO))
    }

    // MARK: - @Model ↔ DTO (private — @Model must never escape the actor)

    /// The **non-nil payload relationship is the single source of truth** for the
    /// entry's kind — on both the read path (here) and the write path (`apply` /
    /// `setPayload` derive the current kind from the payload, never from `entryType`).
    /// The kind is resolved via `Kind(payloadOf:)`, so the scan order lives in exactly
    /// one place. `entryType` is now only a write-only denormalized mirror of that fact,
    /// so it can no longer act as a second, divergent source. The mirror column is
    /// retained only because dropping it outright would require a versioned
    /// `MigrationStage`; see `EntryModel.entryType`.
    private static func toDTO(_ m: EntryModel) -> RegisteredItemDTO {
        var dto = RegisteredItemDTO(
            id: m.id,
            name: m.name,
            sortIndex: m.sortIndex,
            targetKind: "",
            path: nil,
            commandLine: nil,
            workingDirectory: nil,
            executable: nil,
            arguments: nil,
            handlerKind: "",
            appBundleIdentifier: nil,
            terminal: nil,
            applescriptSource: nil,
            categoryID: m.category?.id,
            isHiddenFromMenuBar: m.isHiddenFromMenuBar
        )
        // The `guard let` unwraps are guaranteed to succeed for the matched case
        // (`Kind(payloadOf:)` derives the kind from that very payload); they exist only
        // because the compiler can't see that. `nil` is a partial/corrupt row with no
        // payload — it keeps the empty `targetKind`, as before.
        switch Kind(payloadOf: m) {
        case .browse:
            guard let browse = m.browse else { break }
            dto.targetKind = TargetKind.path.rawValue
            dto.path = browse.path
            if let bundle = browse.appBundleIdentifier {
                dto.handlerKind = HandlerKind.app.rawValue
                dto.appBundleIdentifier = bundle
            } else {
                dto.handlerKind = HandlerKind.defaultApp.rawValue
            }
        case .command:
            guard let command = m.command else { break }
            dto.targetKind = TargetKind.command.rawValue
            dto.commandLine = command.commandLine
            dto.workingDirectory = command.workingDirectory
            // `sink` already holds the persisted `HandlerKind` rawValue
            // ("background"/"terminal"); passed through verbatim.
            dto.handlerKind = command.sink
        case .applescript:
            guard let applescript = m.applescript else { break }
            dto.targetKind = TargetKind.applescript.rawValue
            dto.handlerKind = HandlerKind.applescript.rawValue
            dto.applescriptSource = applescript.source
        case .slider:
            guard let slider = m.slider else { break }
            Self.applySlider(slider, to: &dto)
        case nil:
            break
        }
        return dto
    }

    /// Writes the slider payload onto `dto`. Extracted so `toDTO`'s switch stays within the
    /// function-length budget. The command line is reused from the shared `commandLine`
    /// field (same as a command entry); only the numeric bounds/step/value are slider-specific.
    private static func applySlider(_ slider: SliderEntryModel, to dto: inout RegisteredItemDTO) {
        dto.targetKind = TargetKind.slider.rawValue
        dto.handlerKind = HandlerKind.slider.rawValue
        dto.commandLine = slider.commandLine
        dto.sliderMinValue = slider.minValue
        dto.sliderMaxValue = slider.maxValue
        dto.sliderStep = slider.step
        dto.sliderCurrentValue = slider.currentValue
    }

    // Instance methods: payload tables are created/updated/deleted through the
    // modelContext, so these cannot be static.

    func makeModel(_ dto: RegisteredItemDTO) -> EntryModel {
        let kind = Kind(targetKind: dto.targetKind)
        // `entryType` mirror: the kind's rawValue, or the raw string for an unknown
        // kind (preserves the legacy column value for a row we can't classify).
        let model = EntryModel(id: dto.id, name: dto.name, sortIndex: dto.sortIndex,
                               entryType: kind?.rawValue ?? dto.targetKind,
                               isHiddenFromMenuBar: dto.isHiddenFromMenuBar ?? false)
        modelContext.insert(model)
        if let kind {
            setPayload(kind: kind, from: dto, on: model)
        } else {
            // Unreachable in practice. The index row is stored without a payload; `toDTO`
            // then yields an empty `targetKind`, which `RegisteredItemMapper` rejects on
            // read — the Repository's `decodeOrRecover` logs it and recovers an empty
            // File/Directory entry. We log-and-continue rather than throw so a single bad
            // row can't fail the whole transaction and lose every legitimate entry.
            Self.log.error("""
                makeModel: unknown targetKind '\(dto.targetKind, privacy: .public)' — \
                stored a payload-less index row; recovered as an empty entry on read (upstream mapper bug?)
                """)
        }
        return model
    }

    func apply(_ dto: RegisteredItemDTO, to m: EntryModel) {
        m.name = dto.name
        m.sortIndex = dto.sortIndex
        m.isHiddenFromMenuBar = dto.isHiddenFromMenuBar ?? false
        // Ownership (the `category` relationship) is reconciled by the caller.
        guard let kind = Kind(targetKind: dto.targetKind) else {
            Self.log.error("""
                apply: unknown targetKind '\(dto.targetKind, privacy: .public)' — \
                payload left unchanged (upstream mapper bug?)
                """)
            return
        }
        // The **current** kind is read from the non-nil payload — the single source of
        // truth — not from the `entryType` mirror. If the kind changed on this edit, drop
        // the old payload so we never carry a stale row from a different table. (If the
        // payload and the old mirror had ever diverged, trusting the payload self-heals it.)
        if Kind(payloadOf: m) != kind {
            clearPayload(of: m)
        }
        setPayload(kind: kind, from: dto, on: m)
        // Keep the write-only `entryType` mirror consistent with the payload SSoT.
        m.entryType = kind.rawValue
    }

    /// Creates or updates the single payload row matching `kind`. `kind` is decoded from
    /// the DTO's target kind at the boundary, never read back from the `entryType` mirror.
    /// The `switch` is exhaustive (no `default`), so a new `Kind` case is a compile error
    /// here until it is handled — there is no silent no-op path.
    private func setPayload(kind: Kind, from dto: RegisteredItemDTO, on m: EntryModel) {
        switch kind {
        case .browse:
            let bundle = dto.handlerKind == HandlerKind.app.rawValue ? dto.appBundleIdentifier : nil
            if let existing = m.browse {
                existing.path = dto.path ?? ""
                existing.appBundleIdentifier = bundle
            } else {
                let payload = BrowseEntryModel(path: dto.path ?? "", appBundleIdentifier: bundle)
                modelContext.insert(payload)
                m.browse = payload
            }
        case .command:
            if let existing = m.command {
                existing.commandLine = dto.commandLine ?? ""
                existing.workingDirectory = dto.workingDirectory
                // `sink` (the model/domain term, `CommandSink`) and the DTO's
                // `handlerKind` are the same concept ("background" | "terminal"); the
                // name differs only because the DTO `handlerKind` also spans the browse
                // handlers (defaultApp/app) and applescript.
                existing.sink = dto.handlerKind
            } else {
                let payload = CommandEntryModel(
                    commandLine: dto.commandLine ?? "",
                    workingDirectory: dto.workingDirectory,
                    sink: dto.handlerKind
                )
                modelContext.insert(payload)
                m.command = payload
            }
        case .applescript:
            if let existing = m.applescript {
                existing.source = dto.applescriptSource ?? ""
            } else {
                let payload = AppleScriptEntryModel(source: dto.applescriptSource ?? "")
                modelContext.insert(payload)
                m.applescript = payload
            }
        case .slider:
            setSliderPayload(from: dto, on: m)
        }
    }

    /// Creates or updates the slider payload row. Extracted so `setPayload`'s switch stays
    /// within the function-length budget. `commandLine` is the shared field; the numeric
    /// fields default defensively if a DTO arrives without them (an upstream-mapper bug —
    /// the mapper rejects such rows on read, so this is just a non-crashing fallback).
    private func setSliderPayload(from dto: RegisteredItemDTO, on m: EntryModel) {
        if let existing = m.slider {
            existing.commandLine = dto.commandLine ?? ""
            existing.minValue = dto.sliderMinValue ?? 0
            existing.maxValue = dto.sliderMaxValue ?? 0
            existing.step = dto.sliderStep ?? 1
            existing.currentValue = dto.sliderCurrentValue ?? 0
        } else {
            let payload = SliderEntryModel(
                commandLine: dto.commandLine ?? "",
                minValue: dto.sliderMinValue ?? 0,
                maxValue: dto.sliderMaxValue ?? 0,
                step: dto.sliderStep ?? 1,
                currentValue: dto.sliderCurrentValue ?? 0
            )
            modelContext.insert(payload)
            m.slider = payload
        }
    }

    private func clearPayload(of m: EntryModel) {
        if let payload = m.browse { modelContext.delete(payload); m.browse = nil }
        if let payload = m.command { modelContext.delete(payload); m.command = nil }
        if let payload = m.applescript { modelContext.delete(payload); m.applescript = nil }
        if let payload = m.slider { modelContext.delete(payload); m.slider = nil }
    }
}
