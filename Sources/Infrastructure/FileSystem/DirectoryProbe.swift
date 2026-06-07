import Foundation

/// Reads filesystem facts via `FileManager`. Holds no state, so it is trivially
/// `Sendable` — declared explicitly to match the other Infrastructure adapters
/// (the `DirectoryProbeProtocol` already requires it).
final class DirectoryProbe: DirectoryProbeProtocol, Sendable {
    var homeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }
}
