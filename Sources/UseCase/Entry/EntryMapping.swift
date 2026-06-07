import Foundation

// MARK: - AppChoicePayload ↔ AppChoice

extension AppChoicePayload {
    var toDomain: AppChoice {
        switch self {
        case .default:
            return .default
        case let .app(bundleIdentifier):
            return .app(bundleIdentifier: bundleIdentifier)
        }
    }
}

extension AppChoice {
    var toPayload: AppChoicePayload {
        switch self {
        case .default:
            return .default
        case let .app(bundleIdentifier):
            return .app(bundleIdentifier: bundleIdentifier)
        }
    }
}

// MARK: - CommandSinkPayload ↔ CommandSink

extension CommandSinkPayload {
    var toDomain: CommandSink {
        switch self {
        case .background: return .background
        case .terminal:   return .terminal
        }
    }
}

extension CommandSink {
    var toPayload: CommandSinkPayload {
        switch self {
        case .background: return .background
        case .terminal:   return .terminal
        }
    }
}

// MARK: - BrowsePayload ↔ BrowseEntry

extension BrowsePayload {
    var toDomain: BrowseEntry {
        BrowseEntry(url: URL(fileURLWithPath: path), app: app.toDomain)
    }
}

extension BrowseEntry {
    var toPayload: BrowsePayload {
        BrowsePayload(path: url.path, app: app.toPayload)
    }
}

// MARK: - CommandPayload ↔ CommandEntry

extension CommandPayload {
    var toDomain: CommandEntry {
        // workingDirectory is carried verbatim (a fixed path, nil, or the
        // `<WORKING_DIRECTORY>` sentinel) — the sentinel is resolved to the global
        // current directory at execution time, not here.
        CommandEntry(
            line: commandLine,
            workingDirectory: workingDirectory,
            sink: sink.toDomain
        )
    }
}

extension CommandPayload {
    /// Builds the domain `CommandEntry` with the `<WORKING_DIRECTORY>` sentinel resolved
    /// to the global `currentDirectory` (a no-op for a fixed path or `nil`). Used by the
    /// execution use cases so a templated command runs in the current directory.
    func toDomain(resolvingCurrentDirectory currentDirectory: URL) -> CommandEntry {
        var entry = toDomain
        if entry.workingDirectory == WorkingDirectoryToken.current {
            entry.workingDirectory = currentDirectory.path
        }
        return entry
    }
}

extension CommandEntry {
    var toPayload: CommandPayload {
        CommandPayload(
            commandLine: line,
            workingDirectory: workingDirectory,
            sink: sink.toPayload
        )
    }
}

// MARK: - AppleScriptPayload ↔ AppleScriptEntry

extension AppleScriptPayload {
    var toDomain: AppleScriptEntry { AppleScriptEntry(source: source) }
}

extension AppleScriptEntry {
    var toPayload: AppleScriptPayload { AppleScriptPayload(source: source) }
}

// MARK: - SliderPayload ↔ SliderEntry

extension SliderPayload {
    var toDomain: SliderEntry {
        SliderEntry(
            commandLine: commandLine,
            minValue: minValue,
            maxValue: maxValue,
            step: step,
            currentValue: currentValue
        )
    }

    /// Builds a background `CommandEntry` with `<VALUE>` replaced by `value` (formatted per
    /// `step`). Used by `RunSliderUseCase`. Slider commands always run in the background, and
    /// (product decision: run in the global current directory) set that resolved path as cwd.
    func toCommandDomain(value: Double, currentDirectory: URL) -> CommandEntry {
        let rendered = commandLine.replacingOccurrences(
            of: SliderValueToken.placeholder,
            with: SliderValueFormatter.format(value, step: step)
        )
        return CommandEntry(line: rendered, workingDirectory: currentDirectory.path, sink: .background)
    }
}

extension SliderEntry {
    var toPayload: SliderPayload {
        SliderPayload(
            commandLine: commandLine,
            minValue: minValue,
            maxValue: maxValue,
            step: step,
            currentValue: currentValue
        )
    }
}

// MARK: - EntryKindPayload ↔ EntryKind

extension EntryKindPayload {
    var toDomain: EntryKind {
        switch self {
        case let .browse(browse):
            return .browse(browse.toDomain)
        case let .command(command):
            return .command(command.toDomain)
        case let .appleScript(script):
            return .appleScript(script.toDomain)
        case let .slider(slider):
            return .slider(slider.toDomain)
        }
    }
}

extension EntryKind {
    var toPayload: EntryKindPayload {
        switch self {
        case let .browse(browse):
            return .browse(browse.toPayload)
        case let .command(command):
            return .command(command.toPayload)
        case let .appleScript(script):
            return .appleScript(script.toPayload)
        case let .slider(slider):
            return .slider(slider.toPayload)
        }
    }
}

// MARK: - SavedEntry → SavedEntryResponse

extension SavedEntryResponse {
    init(from item: SavedEntry) {
        self.init(
            id: item.id,
            name: item.name,
            kind: item.kind.toPayload,
            categoryID: item.categoryID,
            isRecovered: item.isRecovered,
            isHiddenFromMenuBar: item.isHiddenFromMenuBar
        )
    }
}
