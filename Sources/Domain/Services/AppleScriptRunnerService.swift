import Foundation

final class AppleScriptRunnerService: AppleScriptRunnerServiceProtocol, Sendable {
    private let launcher: any AppleScriptLauncherRepositoryProtocol

    init(launcher: any AppleScriptLauncherRepositoryProtocol) {
        self.launcher = launcher
    }

    func run(_ entry: AppleScriptEntry) async throws -> String? {
        try await launcher.runAppleScript(source: entry.source)
    }
}
