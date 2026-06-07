import Foundation
import SwiftData

/// Per-type table for AppleScript entries — holds only the source.
@Model
final class AppleScriptEntryModel {
    var source: String                // required

    var entry: EntryModel?            // inverse of EntryModel.applescript (cascade parent)

    init(source: String) {
        self.source = source
    }
}
