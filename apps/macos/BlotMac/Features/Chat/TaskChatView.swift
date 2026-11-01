import BlotDesign
import SwiftUI
struct TaskChatView: View {
    let projectID: String
    let task: TaskItem
    var body: some View {
        if let id = UUID(uuidString: task.id) { RunWorkspaceView(runID: id).id(id) }
    }
}
