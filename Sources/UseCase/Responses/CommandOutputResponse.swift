import Foundation

/// One step of a streaming command run, surfaced to Presentation: a slice of
/// output, or the terminal exit status with its success flag.
enum CommandOutputResponse: Equatable, Sendable {
    case stdout(String)
    case stderr(String)
    case exit(code: Int32, succeeded: Bool)

    init(from event: CommandOutputEvent) {
        switch event {
        case .stdout(let text): self = .stdout(text)
        case .stderr(let text): self = .stderr(text)
        case .exit(let code):   self = .exit(code: code, succeeded: code == 0)
        }
    }
}
