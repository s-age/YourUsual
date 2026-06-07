import Foundation
import os
import UserNotifications

/// Posts user notifications via `UserNotifications`.
final class NotificationDataSource: NotifierProtocol, Sendable {
    private static let log = Logger(subsystem: "com.yourusual.app", category: "NotificationDataSource")

    func notify(title: String, body: String) async {
        // `UNUserNotificationCenter.current()` aborts when there is no bundle
        // identifier (bare executable: Xcode scheme, `swift run`). Skip quietly so
        // running a background command there doesn't crash; notifications are
        // delivered from the installed, code-signed `.app` bundle.
        guard Bundle.main.bundleIdentifier != nil else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        // Best-effort: notifications are non-fatal, so a delivery failure must not
        // throw or crash — but log it so the failure isn't completely invisible.
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Self.log.error("Failed to post notification: \(error.localizedDescription, privacy: .public)")
        }
    }
}
