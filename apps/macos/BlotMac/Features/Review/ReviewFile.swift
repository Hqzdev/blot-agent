import BlotDesign
import Foundation

struct ReviewFile: Identifiable {
    var id: String { path }
    let path: String
    let added: Int
    let removed: Int
    let patch: String
    var lines: [DiffLine] { UnifiedDiffParser.parse(patch) }
}

