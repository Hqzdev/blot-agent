import BlotDomain
import SwiftUI

struct WorkspaceTaskStateLabel: View {
    let state: BlotV3.TaskState
    @Environment(WorkspaceStore.self) private var store
    var body: some View { Text(title) }
    private var title: String {
        let russian = store.language == "ru"
        switch state {
        case .queued: return russian ? "В очереди" : "Queued"
        case .running, .planning: return russian ? "Выполняется" : "Running"
        case .paused: return store.t("Paused")
        case .completed: return russian ? "Выполнено" : "Completed"
        case .canceled: return russian ? "Остановлено" : "Canceled"
        case .failed: return russian ? "Ошибка выполнения" : "Failed"
        case .interrupted: return russian ? "Выполнение прервано" : "Interrupted"
        case .waiting_approval: return russian ? "Ожидает подтверждения" : "Waiting for approval"
        case .waiting_user: return russian ? "Нужны ваши данные" : "Waiting for input"
        case .draft: return russian ? "Черновик" : "Draft"
        }
    }
}
