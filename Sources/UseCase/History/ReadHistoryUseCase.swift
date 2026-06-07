import Foundation

final class ReadHistoryUseCase: AsyncUseCase, Sendable {
    private let history: any RunHistoryServiceProtocol

    init(history: any RunHistoryServiceProtocol) {
        self.history = history
    }

    func execute(_ request: ReadHistoryRequest) async throws -> [RunHistoryResponse] {
        let records: [RunRecord]
        if let entryID = request.entryID {
            records = try await history.list(forEntry: entryID)
        } else {
            records = try await history.listAll()
        }
        return records.map(RunHistoryResponse.init(from:))
    }
}
