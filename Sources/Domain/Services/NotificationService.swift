import Foundation

final class NotificationService: NotificationServiceProtocol, Sendable {
    private static let stderrPreviewLimit = 200

    private let notifier: any NotifierRepositoryProtocol

    init(notifier: any NotifierRepositoryProtocol) {
        self.notifier = notifier
    }

    func notifyIfNeeded(name: String, result: CommandResult?) async {
        guard let result else { return }
        let body = result.succeeded
            ? "Completed (exit 0)"
            : "Failed (exit \(result.exitCode))\n\(result.stderr.prefix(Self.stderrPreviewLimit))"
        await notifier.notify(title: name, body: body)
    }

    func notifyCompletion(name: String) async {
        await notifier.notify(title: name, body: "Completed")
    }

    func notifyFailure(name: String, error: any Error) async {
        await notifier.notify(title: name, body: error.localizedDescription)
    }
}
