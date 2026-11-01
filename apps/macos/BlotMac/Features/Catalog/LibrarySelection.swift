import BlotDesign
import Foundation
import Observation

@MainActor
@Observable
final class LibrarySelection {
    var selectedID: UUID?
    var search = ""
    func clear() {
        selectedID = nil
        search = ""
    }
}
