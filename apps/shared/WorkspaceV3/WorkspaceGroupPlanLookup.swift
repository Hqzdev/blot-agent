import BlotDomain
import BlotWorkspace

extension WorkspaceStore {
    func groupPlan(for message: BlotV3.Message) -> WorkspaceGroupPlanProgress? {
        chatContent.plan(for: message)
    }
}
