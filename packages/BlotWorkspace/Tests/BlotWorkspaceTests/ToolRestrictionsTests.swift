import Testing
@testable import BlotWorkspace

@Test func explicitCurrentTurnConstraintsNarrowOperationsWithoutBlockingRequestedDrafts() {
    for text in ["Только обнаружение ресурсов", "Only resource discovery", "Только реальные списки ресурсов"] {
        let restrictions = WorkspaceToolRestrictions(userRequest: text)
        #expect(restrictions.allows(operation: "resources"))
        #expect(!restrictions.allows(operation: "list"))
        #expect(!restrictions.allows(operation: "create"))
    }
    for text in ["Только чтение", "Ничего не создавать и не менять", "Read only"] {
        let restrictions = WorkspaceToolRestrictions(userRequest: text)
        #expect(restrictions.allows(operation: "list"))
        #expect(!restrictions.allows(operation: "create"))
        #expect(!restrictions.allows(operation: "run"))
    }
    let draft = WorkspaceToolRestrictions(userRequest: "Создай черновик, не отправляй письмо")
    #expect(draft.allows(operation: "create"))
    #expect(!draft.allows(operation: "send"))
}
