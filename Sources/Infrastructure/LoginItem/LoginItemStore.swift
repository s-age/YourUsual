import ServiceManagement

/// Backs the login-item toggle with `SMAppService.mainApp` — registering the app
/// bundle as a login item (the modern replacement for the legacy login-items API).
final class LoginItemStore: LoginItemStoreProtocol, Sendable {
    func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}
