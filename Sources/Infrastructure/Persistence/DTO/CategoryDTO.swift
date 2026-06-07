import Foundation

struct CategoryDTO: Sendable {
    var id: UUID
    var name: String
    var sortIndex: Int
    // Not Codable (legacy registry.json carries no categories), so a plain non-optional
    // default suffices — no missing-key decode concern. Defaults to visible.
    var isHiddenFromMenuBar: Bool = false
}
