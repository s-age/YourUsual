import Foundation
import SwiftData

/// Per-type table for browse entries — holds only the fields a browse entry needs.
@Model
final class BrowseEntryModel {
    var path: String                  // required
    var appBundleIdentifier: String?  // nil = open with the system default app

    var entry: EntryModel?            // inverse of EntryModel.browse (cascade parent)

    init(path: String, appBundleIdentifier: String?) {
        self.path = path
        self.appBundleIdentifier = appBundleIdentifier
    }
}
