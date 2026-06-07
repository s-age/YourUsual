import Foundation
@testable import YourUsual

// MARK: - Shared call-counting repository mocks for the behaviour services
//
// Split per launch concern (mirrors the production protocol split): consumed by
// `BrowseLauncherServiceTests` and `CommandRunnerServiceTests`. Mutation is driven by
// the service under test on a single task, so `@unchecked Sendable` is acceptable here.

final class MockBrowseLauncherRepository: BrowseLauncherRepositoryProtocol, @unchecked Sendable {
    var openPathCallCount = 0
    var openedPath: URL?
    var openedBundleID: String?

    func openPath(_ path: URL, withApp bundleIdentifier: String?) async throws {
        openPathCallCount += 1
        openedPath = path
        openedBundleID = bundleIdentifier
    }
}

final class MockCommandLauncherRepository: CommandLauncherRepositoryProtocol, @unchecked Sendable {
    var runCommandInTerminalCallCount = 0
    var runCommandInTerminalCommandLine: String?
    var runCommandInTerminalBundleID: String?
    var runCommandInTerminalLaunchMode: TerminalLaunchMode?

    var runCommandInTerminalCurrentDirectory: URL?

    var streamCommandInBackgroundCallCount = 0
    var streamCommandInBackgroundCommandLine: String?
    var streamCommandInBackgroundWorkingDirectory: URL?
    var streamCommandInBackgroundCurrentDirectory: URL?
    var streamEvents: [CommandOutputEvent] = []

    func streamCommandInBackground(commandLine: String,
                                   directories: CommandDirectories) -> any AsyncSequence<CommandOutputEvent, Error> {
        streamCommandInBackgroundCallCount += 1
        streamCommandInBackgroundCommandLine = commandLine
        streamCommandInBackgroundWorkingDirectory = directories.workingDirectory
        streamCommandInBackgroundCurrentDirectory = directories.currentDirectory
        let events = streamEvents
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }

    func runCommandInTerminal(commandLine: String,
                              directories: CommandDirectories,
                              bundleIdentifier: String,
                              launchMode: TerminalLaunchMode) async throws {
        runCommandInTerminalCallCount += 1
        runCommandInTerminalCommandLine = commandLine
        runCommandInTerminalCurrentDirectory = directories.currentDirectory
        runCommandInTerminalBundleID = bundleIdentifier
        runCommandInTerminalLaunchMode = launchMode
    }
}

final class MockAppleScriptLauncherRepository: AppleScriptLauncherRepositoryProtocol, @unchecked Sendable {
    var runAppleScriptCallCount = 0
    var runAppleScriptSource: String?
    var runAppleScriptResult: String?

    func runAppleScript(source: String) async throws -> String? {
        runAppleScriptCallCount += 1
        runAppleScriptSource = source
        return runAppleScriptResult
    }
}

/// Configurable mock of the global terminal-settings repository.
final class MockTerminalSettingsRepository: TerminalSettingsRepositoryProtocol, @unchecked Sendable {
    var preference: TerminalPreference = .default
    var installed: Set<String> = [TerminalApp.terminal.bundleIdentifier]
    var resolved: BrowsedApp?
    var savePreferenceCallCount = 0
    var normalizeStoredPreferenceResult = false
    var normalizeStoredPreferenceCallCount = 0

    func loadPreference() -> TerminalPreference { preference }
    func savePreference(_ preference: TerminalPreference) throws {
        savePreferenceCallCount += 1
        self.preference = preference
    }
    func normalizeStoredPreference() throws -> Bool {
        normalizeStoredPreferenceCallCount += 1
        return normalizeStoredPreferenceResult
    }
    func isInstalled(_ app: TerminalApp) -> Bool { installed.contains(app.bundleIdentifier) }
    func resolveApp(at url: URL) -> BrowsedApp? { resolved }
}

final class MockNotifierRepository: NotifierRepositoryProtocol, @unchecked Sendable {
    var notifyCallCount = 0
    var notifyTitle: String?
    var notifyBody: String?

    func notify(title: String, body: String) async {
        notifyCallCount += 1
        notifyTitle = title
        notifyBody = body
    }
}

final class MockCurrentDirectoryRepository: CurrentDirectoryRepositoryProtocol, @unchecked Sendable {
    var preference: CurrentDirectoryPreference = .default
    var loadCallCount = 0
    var savedPreferences: [CurrentDirectoryPreference] = []
    var saveError: Error?

    func loadPreference() -> CurrentDirectoryPreference {
        loadCallCount += 1
        return preference
    }

    func savePreference(_ preference: CurrentDirectoryPreference) throws {
        savedPreferences.append(preference)
        if let saveError { throw saveError }
        self.preference = preference
    }
}
