import Foundation

struct ReadHistoryRequest: UseCaseRequest {
    let entryID: UUID?      // nil → all history; non-nil → one entry's history
}

struct DeleteHistoryRequest: UseCaseRequest {
    enum Scope: Sendable {
        case run(UUID)      // one run
        case entry(UUID)    // all runs of one entry
        case all            // everything
    }
    let scope: Scope
}
