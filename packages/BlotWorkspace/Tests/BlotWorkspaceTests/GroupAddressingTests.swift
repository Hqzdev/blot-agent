import Foundation
import Testing
@testable import BlotWorkspace

@Test func explicitNamedTasksKeepTheirOwnersAndOrder() throws {
    let ceo = UUID(), mail = UUID(), sales = UUID(), mira = UUID()
    let roster = [ceo: "CEO", mail: "Mail Manager", sales: "Sales Manager", mira: "Mira"]
    let result = try #require(WorkspaceGroupDecision.addressedTasks(
        "Новая проверка. CEO — назови критерий. Mail Manager — предложи тему. Sales Manager — предложи вопрос. Каждый отвечает сам.", members: roster))
    #expect(result.mode == .team)
    #expect(result.assignments?.map(\.agentID) == [ceo, mail, sales])
    #expect(result.assignments?.first?.task == "назови критерий.")
    #expect(result.assignments?.last?.task == "предложи вопрос. Каждый отвечает сам.")
    #expect(WorkspaceGroupDecision.addressedTasks("Обсуди ответ CEO с Mail Manager.", members: roster) == nil)
    #expect(WorkspaceGroupDecision.addressedTasks("CEO — задача. CEO — ещё задача.", members: roster) == nil)
    #expect(WorkspaceGroupDecision.addressedTasks("NotCEO — задача. Mail Manager — тема.", members: roster) == nil)
}
