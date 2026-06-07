import Foundation

/// The global current directory. `path` is the raw stored value (an absolute path);
/// `nil` means "reset to the default", which the store maps to the home directory. Persisted
/// to a state file (shared with the `your-usual cd` CLI), so it survives relaunch; the store
/// self-heals a missing file to home, so a loaded value is in practice always a concrete path.
struct CurrentDirectoryPreference: Equatable, Sendable {
    var path: String?

    static let `default` = CurrentDirectoryPreference(path: nil)
}
