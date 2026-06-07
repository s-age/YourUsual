import Foundation

/// Bridges the launch-at-login domain intent to the infrastructure store.
/// No decision-making — a straight pass-through to `LoginItemStore`.
final class LaunchAtLoginRepository: LaunchAtLoginRepositoryProtocol, Sendable {
    private let store: any LoginItemStoreProtocol

    init(store: any LoginItemStoreProtocol) {
        self.store = store
    }

    func isEnabled() -> Bool {
        store.isEnabled()
    }

    func setEnabled(_ enabled: Bool) throws {
        try store.setEnabled(enabled)
    }
}
