import Foundation

final class ReadLaunchAtLoginUseCase: SyncUseCase, Sendable {
    private let launchAtLogin: any LaunchAtLoginServiceProtocol

    init(launchAtLogin: any LaunchAtLoginServiceProtocol) {
        self.launchAtLogin = launchAtLogin
    }

    func execute(_ request: ReadLaunchAtLoginRequest) throws -> Bool {
        launchAtLogin.isEnabled()
    }
}
