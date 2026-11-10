import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

@Test func displayedAgentReferencesRespectNamesUnicodeBoundariesAndExplicitRouting() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("db"))
    let identity = try await repository.localIdentity()
    let service = WorkspaceAgentService(repository: repository, identity: identity)
    for name in ["CEO", "CEO Assistant", "Sales Manager", "Иван"] {
        _ = try await service.save(commandID: UUID(), draft: .init(name: name, instructions: "Help"))
    }
    let agents = try await repository.projection(identity: identity).agents
    let text = "🐈 CEO назвал критерий, Sales Manager — тему. @Иван ответил CEO Assistant. NotCEO CEOish foo@CEO.com https://CEO.com CEO."
    let names = Dictionary(uniqueKeysWithValues: agents.map { ($0.metadata.id, $0.name) })
    let references = try WorkspaceNamedReferences.find(text, names: names)
    let value = text as NSString
    #expect(references.map { value.substring(with: NSRange(location: $0.startUTF16, length: $0.lengthUTF16)) }
        == ["CEO", "Sales Manager", "@Иван", "CEO Assistant", "CEO"])
    let plain = "CEO назвал критерий."
    #expect(try WorkspaceGroupMentions.extract(plain, agents: agents).isEmpty)
    let plainReferences = try WorkspaceNamedReferences.find(plain, names: names).map {
        try BlotV3.MessageMention(agentId: $0.id, startUTF16: $0.startUTF16, lengthUTF16: $0.lengthUTF16)
    }
    #expect(WorkspaceGroupMentions.recipients(plain, mentions: plainReferences).isEmpty)
    let addressed = "@CEO, проверь результат."
    let ceo = try #require(agents.first { $0.name == "CEO" })
    #expect(WorkspaceGroupMentions.recipients(addressed, mentions: try WorkspaceGroupMentions.extract(addressed, agents: agents)) == [ceo.metadata.id])
    try await repository.close()
}

@Test func displayedSkillReferencesUseCompleteKnownTitlesAndShareAgentOverlapRules() throws {
    let skill = UUID(), shortSkill = UUID(), agent = UUID()
    let text = "CEO применит Анализ продаж и @Проверка писем. Анализ продажности не совпадает."
    let names = [agent: "CEO", shortSkill: "Анализ", skill: "Анализ продаж", UUID(): "Проверка писем"]
    let found = try WorkspaceNamedReferences.find(text, names: names)
    let string = text as NSString
    #expect(found.map { string.substring(with: NSRange(location: $0.startUTF16, length: $0.lengthUTF16)) }
        == ["CEO", "Анализ продаж", "@Проверка писем", "Анализ"])
    #expect(found[1].id == skill)
}
