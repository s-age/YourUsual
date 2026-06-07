import Foundation

/// Owns the launch-at-login business intent: report and toggle whether the app
/// registers itself to start at login.
final class LaunchAtLoginService: LaunchAtLoginServiceProtocol, Sendable {
    private let repository: any LaunchAtLoginRepositoryProtocol

    init(repository: any LaunchAtLoginRepositoryProtocol) {
        self.repository = repository
    }

    func isEnabled() -> Bool {
        repository.isEnabled()
    }

    func setEnabled(_ enabled: Bool) throws {
        try repository.setEnabled(enabled)
    }
}
