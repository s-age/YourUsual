import Foundation

/// Runs an AppleScript source, backing `AppleScriptRunnerService`.
final class AppleScriptLauncherRepository: AppleScriptLauncherRepositoryProtocol, Sendable {
    private let appleScriptRunner: any AppleScriptRunnerProtocol

    init(appleScriptRunner: any AppleScriptRunnerProtocol) {
        self.appleScriptRunner = appleScriptRunner
    }

    func runAppleScript(source: String) async throws -> String? {
        try await appleScriptRunner.run(source: source)
    }
}
