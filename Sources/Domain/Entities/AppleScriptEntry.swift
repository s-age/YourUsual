import Foundation

struct AppleScriptEntry: Equatable, Sendable {
    var source: String

    init(source: String) {
        self.source = source
    }
}
