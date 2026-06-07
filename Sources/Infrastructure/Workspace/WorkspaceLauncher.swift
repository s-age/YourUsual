import AppKit
import Foundation

/// Opens a path with the default app or a specific app via `NSWorkspace`.
final class WorkspaceLauncher: WorkspaceLauncherProtocol, Sendable {
    func open(path: URL, withAppBundleIdentifier bundleIdentifier: String?) async throws {
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw OperationError.targetNotFound(path: path.path)
        }

        guard let bundleIdentifier else {
            // The file exists (checked above), so a `false` here is an open
            // failure, not a missing target — report it as such rather than
            // misleadingly claiming the path is gone.
            guard NSWorkspace.shared.open(path) else {
                throw OperationError.targetOpenFailed(path: path.path)
            }
            return
        }

        guard let appURL = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw OperationError.appNotFound(bundleIdentifier: bundleIdentifier)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open([path],
                                    withApplicationAt: appURL,
                                    configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
