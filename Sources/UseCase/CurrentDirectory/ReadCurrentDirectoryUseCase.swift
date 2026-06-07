import Foundation

/// Reports the global current directory, resolved to a valid absolute path: the raw
/// in-memory value run through `WorkingDirectoryResolver`, which falls back to home when
/// it is unset or no longer a real directory.
final class ReadCurrentDirectoryUseCase: SyncUseCase, Sendable {
    private let currentDirectory: any CurrentDirectoryServiceProtocol
    private let resolver: any WorkingDirectoryResolverProtocol

    init(currentDirectory: any CurrentDirectoryServiceProtocol,
         resolver: any WorkingDirectoryResolverProtocol) {
        self.currentDirectory = currentDirectory
        self.resolver = resolver
    }

    func execute(_ request: ReadCurrentDirectoryRequest) throws -> CurrentDirectoryResponse {
        CurrentDirectoryResponse(path: resolver.resolve(currentDirectory.current().path).path)
    }
}
