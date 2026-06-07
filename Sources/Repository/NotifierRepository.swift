import Foundation

final class NotifierRepository: NotifierRepositoryProtocol, Sendable {
    private let notifier: any NotifierProtocol

    init(notifier: any NotifierProtocol) {
        self.notifier = notifier
    }

    func notify(title: String, body: String) async {
        await notifier.notify(title: title, body: body)
    }
}
