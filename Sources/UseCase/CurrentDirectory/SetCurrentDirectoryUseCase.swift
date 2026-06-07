import Foundation

/// Replaces the global current directory (in memory) and reports the resulting resolved
/// path — the stored raw value run through `WorkingDirectoryResolver`, so the caller sees
/// exactly what later command runs will use (including the home fallback for an empty or
/// non-existent input).
final class SetCurrentDirectoryUseCase: SyncUseCase, Sendable {
    private let currentDirectory: any CurrentDirectoryServiceProtocol
    private let resolver: any WorkingDirectoryResolverProtocol

    init(currentDirectory: any CurrentDirectoryServiceProtocol,
         resolver: any WorkingDirectoryResolverProtocol) {
        self.currentDirectory = currentDirectory
        self.resolver = resolver
    }

    func execute(_ request: SetCurrentDirectoryRequest) throws -> CurrentDirectoryResponse {
        try currentDirectory.setPath(request.path)
        return CurrentDirectoryResponse(path: resolver.resolve(currentDirectory.current().path).path)
    }
}
