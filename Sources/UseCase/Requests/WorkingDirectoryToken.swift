import Foundation

/// The sentinel a command entry's working-directory field can hold to mean "run in the
/// global current directory" instead of a fixed path. When present, the execution use
/// cases substitute the resolved current directory at run time (equivalent to
/// `cd "${YOUR_USUAL_CURRENT_DIRECTORY}"`). Defined here — the one spot both the
/// Presentation form (which offers it) and the UseCase (which interprets it) can see.
enum WorkingDirectoryToken {
    static let current = "<WORKING_DIRECTORY>"
}
