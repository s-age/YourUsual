import Foundation

final class ResolveWorkingDirectoryUseCase: SyncUseCase, Sendable {
    private let resolver: any WorkingDirectoryResolverProtocol

    init(resolver: any WorkingDirectoryResolverProtocol) {
        self.resolver = resolver
    }

    func execute(_ request: ResolveWorkingDirectoryRequest) throws -> String {
        resolver.resolve(request.path).path
    }
}
