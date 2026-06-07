import Foundation

final class ResolveTerminalAppUseCase: SyncUseCase, Sendable {
    private let settings: any TerminalSettingsServiceProtocol

    init(settings: any TerminalSettingsServiceProtocol) {
        self.settings = settings
    }

    func execute(_ request: ResolveTerminalAppRequest) throws -> TerminalAppOptionResponse? {
        settings.resolveApp(at: request.url).map(TerminalAppOptionResponse.init(from:))
    }
}
