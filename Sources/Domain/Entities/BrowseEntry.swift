import Foundation

struct BrowseEntry: Equatable, Sendable {
    var url: URL
    var app: AppChoice

    init(url: URL, app: AppChoice) {
        self.url = url
        self.app = app
    }
}
