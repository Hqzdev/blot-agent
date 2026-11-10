import BlotDomain
import SwiftUI

struct WorkspaceSchedulePolicyLabel: View {
    let policy: BlotV3.MissedRunPolicy
    @Environment(WorkspaceStore.self) private var store
    var body: some View { Text(title) }
    private var title: String {
        let russian = store.language == "ru"
        switch policy {
        case .coalesce: return russian ? "Один запуск за всё пропущенное" : "One combined missed run"
        case .catch_up: return russian ? "Догнать пропущенные запуски" : "Catch up missed runs"
        case .skip: return russian ? "Пропустить опоздавшие запуски" : "Skip missed runs"
        }
    }
}
