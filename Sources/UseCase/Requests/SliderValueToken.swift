import Foundation

/// The placeholder a slider's command line carries; the run use case substitutes the
/// current numeric value for it at execution time (same shape as `WorkingDirectoryToken`).
/// Defined once so the Presentation form (which offers it) and the UseCase (which
/// interprets it) share a single spelling.
enum SliderValueToken {
    static let placeholder = "<VALUE>"
}
