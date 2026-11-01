import BlotDesign
import Foundation

enum DiffTone { case context, added, removed, header }

struct DiffLine: Identifiable {
    let id: Int
    let oldNumber: Int?
    let newNumber: Int?
    let text: String
    let tone: DiffTone
}
