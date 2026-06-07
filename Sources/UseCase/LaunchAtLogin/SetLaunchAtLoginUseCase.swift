import Foundation

final class SetLaunchAtLoginUseCase: SyncUseCase, Sendable {
    private let launchAtLogin: any LaunchAtLoginServiceProtocol

    init(launchAtLogin: any LaunchAtLoginServiceProtocol) {
        self.launchAtLogin = launchAtLogin
    }

    /// Applies the change, then reports the system's resulting state — so the
    /// caller reflects what actually took effect rather than the requested value.
    func execute(_ request: SetLaunchAtLoginRequest) throws -> Bool {
        try launchAtLogin.setEnabled(request.enabled)
        return launchAtLogin.isEnabled()
    }
}
