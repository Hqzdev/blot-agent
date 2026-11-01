import BlotDesign
import Foundation
import Observation

/// Краткое представление сохранённого запуска для навигации.
struct WorkSession {
    enum Status: String { case running, paused, stopped }
    let id: String
    let title: String
    let projectID: String
    let status: Status
}

@Observable
final class NewRunState {
    var projectID = ""
    var goal = ""
}
