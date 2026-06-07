import Foundation

/// Transport shape for a command's directory context at the Infrastructure boundary
/// (the Repository converts the Domain `CommandDirectories` into this). `workingDirectory`
/// is where the process/shell runs; `currentDirectory` is exported as
/// `YOUR_USUAL_CURRENT_DIRECTORY`. Kept as a single value so the runner/launcher
/// signatures stay within the parameter-count limit.
struct CommandDirectoriesDTO: Sendable {
    let workingDirectory: URL?
    let currentDirectory: URL
}
