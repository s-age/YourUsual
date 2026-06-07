import Foundation

/// The directory context a registered command runs with:
/// - `workingDirectory`: where the process/shell actually runs (`nil` = inherit default),
///   already resolved (the `<WORKING_DIRECTORY>` sentinel substituted) by the UseCase.
/// - `currentDirectory`: the global current directory, exported to the command's
///   environment as `YOUR_USUAL_CURRENT_DIRECTORY` regardless of where it runs.
///
/// Bundled into one value so the launcher signatures stay within the parameter-count
/// limit and the two directory concerns travel together.
struct CommandDirectories: Equatable, Sendable {
    var workingDirectory: URL?
    var currentDirectory: URL
}
