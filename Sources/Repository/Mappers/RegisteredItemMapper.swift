import Foundation

/// Single source of truth for `RegisteredItemDTO` ⇄ `SavedEntry` conversion. The
/// discriminator strings it encodes/decodes are the shared `TargetKind`/`HandlerKind`
/// vocabulary from the `Constants` leaf — the same enums the Infrastructure store
/// reads/writes — so the encode and decode sides cannot drift, across this mapper *or*
/// across the layer boundary.
enum RegisteredItemMapper {

    // MARK: - Entity → DTO

    static func toDTO(_ item: SavedEntry) -> RegisteredItemDTO {
        let fields = encodeKind(item.kind)
        return RegisteredItemDTO(
            id: item.id,
            name: item.name,
            sortIndex: item.sortIndex,
            targetKind: fields.targetKind,
            path: fields.path,
            commandLine: fields.commandLine,
            workingDirectory: fields.workingDirectory,
            executable: nil,
            arguments: nil,
            handlerKind: fields.handlerKind,
            appBundleIdentifier: fields.appBundleIdentifier,
            terminal: nil,
            applescriptSource: fields.applescriptSource,
            categoryID: item.categoryID,
            isHiddenFromMenuBar: item.isHiddenFromMenuBar,
            sliderMinValue: fields.sliderMinValue,
            sliderMaxValue: fields.sliderMaxValue,
            sliderStep: fields.sliderStep,
            sliderCurrentValue: fields.sliderCurrentValue
        )
    }

    /// The kind-dependent slice of a `RegisteredItemDTO`. The discriminators are `let`,
    /// so Swift's definite-initialization rule forces every switch branch to assign them:
    /// a future `EntryKind`/handler case that forgets is a *compile error*, not a silent
    /// "" sentinel that would persist as an "unknown" kind and be recovered into an empty
    /// entry (lost data). Split out of `toDTO` only to keep that assembler short.
    private struct EncodedKind {
        let targetKind: String
        let handlerKind: String
        var path: String?
        var commandLine: String?
        var workingDirectory: String?
        var appBundleIdentifier: String?
        var applescriptSource: String?
        var sliderMinValue: Double?
        var sliderMaxValue: Double?
        var sliderStep: Double?
        var sliderCurrentValue: Double?
    }

    private static func encodeKind(_ kind: EntryKind) -> EncodedKind {
        switch kind {
        case .browse(let browse):
            let handlerKind: String
            var appBundleIdentifier: String?
            switch browse.app {
            case .default:
                handlerKind = HandlerKind.defaultApp.rawValue
            case .app(let bundleIdentifier):
                handlerKind = HandlerKind.app.rawValue
                appBundleIdentifier = bundleIdentifier
            }
            return EncodedKind(
                targetKind: TargetKind.path.rawValue, handlerKind: handlerKind,
                path: browse.url.path, appBundleIdentifier: appBundleIdentifier
            )
        case .command(let command):
            // workingDirectory stored verbatim (raw path string or the
            // `<WORKING_DIRECTORY>` sentinel); the entity already carries the unresolved
            // string, so no URL conversion here.
            let handlerKind = command.sink == .background
                ? HandlerKind.background.rawValue
                : HandlerKind.terminal.rawValue
            return EncodedKind(
                targetKind: TargetKind.command.rawValue, handlerKind: handlerKind,
                commandLine: command.line, workingDirectory: command.workingDirectory
            )
        case .appleScript(let script):
            return EncodedKind(
                targetKind: TargetKind.applescript.rawValue,
                handlerKind: HandlerKind.applescript.rawValue,
                applescriptSource: script.source
            )
        case .slider(let slider):
            return EncodedKind(
                targetKind: TargetKind.slider.rawValue,
                handlerKind: HandlerKind.slider.rawValue,
                commandLine: slider.commandLine,                 // reuse the `command` field
                sliderMinValue: slider.minValue, sliderMaxValue: slider.maxValue,
                sliderStep: slider.step, sliderCurrentValue: slider.currentValue
            )
        }
    }

    // MARK: - DTO → Entity

    /// Decodes a stored record into a `SavedEntry`. Throws
    /// `OperationError.persistenceFailed` when the discriminators/fields cannot form a
    /// valid kind; the caller decides whether to recover (`recoveredEntity`) or skip.
    static func toEntity(_ dto: RegisteredItemDTO) throws -> SavedEntry {
        SavedEntry(
            id: dto.id,
            name: dto.name,
            kind: try decodeKind(dto),
            sortIndex: dto.sortIndex,
            categoryID: recoveredCategoryID(dto),
            isHiddenFromMenuBar: dto.isHiddenFromMenuBar ?? false   // nil (legacy) = visible
        )
    }

    /// Transport-recovery shape for an undecodable record: an empty File/Directory
    /// entry opened with the default app, preserving identity and the persisted path
    /// when present. This is transport/format recovery (same category as the legacy
    /// `decodeCommandLine` fallback) — not a domain decision; the Repository owns the
    /// *choice* to recover, this only provides the shape.
    static func recoveredEntity(from dto: RegisteredItemDTO) -> SavedEntry {
        // `dto.path ?? ""` is an intentional empty placeholder path when none was stored:
        // the recovered entry exists only to be re-entered or deleted, so the path field
        // is meant to read as "blank, fill me in" (it is never opened as-is). The startup
        // self-heal persists this shape and the user is told to re-enter it.
        SavedEntry(
            id: dto.id,
            name: dto.name,
            kind: .browse(BrowseEntry(url: URL(fileURLWithPath: dto.path ?? ""), app: .default)),
            sortIndex: dto.sortIndex,
            categoryID: recoveredCategoryID(dto),
            // `isRecovered` marks the placeholder so Presentation can warn before an edit
            // overwrites the original. A recovered entry stays visible
            // (`isHiddenFromMenuBar: false`) regardless of the (possibly lost) original
            // visibility, so the user notices it and re-enters it.
            isRecovered: true,
            isHiddenFromMenuBar: false
        )
    }

    /// Orphan recovery, in **one** place: a record persisted before categories existed
    /// (or whose owning category was lost) has no categoryID — fall it back to Default.
    /// Read as transport recovery for a missing field, not a domain re-home rule. This is
    /// the boundary case `arch-repository.md` flags; keeping it single-sourced means a
    /// future move to a Domain Service (e.g. an "Uncategorized" bucket) touches one line.
    private static func recoveredCategoryID(_ dto: RegisteredItemDTO) -> UUID {
        dto.categoryID ?? EntryCategory.defaultID
    }

    private static func decodeKind(_ dto: RegisteredItemDTO) throws -> EntryKind {
        switch TargetKind(rawValue: dto.targetKind) {
        case .path:
            guard let path = dto.path else {
                throw OperationError.persistenceFailed(reason: "missing path for browse entry")
            }
            return .browse(BrowseEntry(url: URL(fileURLWithPath: path), app: try decodeApp(dto)))

        case .command:
            // legacy executable+args fallback は decodeCommandLine に集約
            guard let line = decodeCommandLine(dto), !line.isEmpty else {
                throw OperationError.persistenceFailed(reason: "missing command for command entry")
            }
            return .command(CommandEntry(
                line: line,
                workingDirectory: dto.workingDirectory,
                sink: try decodeSink(dto)
            ))

        case .applescript:
            guard let source = dto.applescriptSource, !source.isEmpty else {
                throw OperationError.persistenceFailed(reason: "missing source for applescript entry")
            }
            return .appleScript(AppleScriptEntry(source: source))

        case .slider:
            // The slider reuses the `commandLine` field; the handler is the single
            // `slider` value, so there is no per-handler sub-switch (unlike browse/command).
            guard let line = dto.commandLine, !line.isEmpty else {
                throw OperationError.persistenceFailed(reason: "missing command for slider entry")
            }
            guard let minValue = dto.sliderMinValue,
                  let maxValue = dto.sliderMaxValue,
                  let step = dto.sliderStep,
                  let currentValue = dto.sliderCurrentValue else {
                throw OperationError.persistenceFailed(reason: "missing numeric fields for slider entry")
            }
            return .slider(SliderEntry(
                commandLine: line, minValue: minValue, maxValue: maxValue,
                step: step, currentValue: currentValue
            ))

        case nil:
            throw OperationError.persistenceFailed(reason: "unknown targetKind: \(dto.targetKind)")
        }
    }

    private static func decodeApp(_ dto: RegisteredItemDTO) throws -> AppChoice {
        switch HandlerKind(rawValue: dto.handlerKind) {
        case .defaultApp:
            return .default
        case .app:
            guard let bundleIdentifier = dto.appBundleIdentifier else {
                throw OperationError.persistenceFailed(reason: "missing appBundleIdentifier for app handler")
            }
            return .app(bundleIdentifier: bundleIdentifier)
        default:
            throw OperationError.persistenceFailed(
                reason: "browse entry needs defaultApp/app handler, got \(dto.handlerKind)"
            )
        }
    }

    private static func decodeSink(_ dto: RegisteredItemDTO) throws -> CommandSink {
        switch HandlerKind(rawValue: dto.handlerKind) {
        case .background:
            return .background
        case .terminal:
            // The terminal app + launch mode is now the global setting; any legacy
            // per-entry `dto.terminal` value is ignored.
            return .terminal
        default:
            throw OperationError.persistenceFailed(
                reason: "command entry needs background/terminal handler, got \(dto.handlerKind)"
            )
        }
    }

    /// Prefer the shell command line; fall back to legacy executable+arguments
    /// so pre-shell-migration entries still load.
    private static func decodeCommandLine(_ dto: RegisteredItemDTO) -> String? {
        if let line = dto.commandLine { return line }
        guard let executable = dto.executable else { return nil }
        return ([executable] + (dto.arguments ?? [])).joined(separator: " ")
    }
}
