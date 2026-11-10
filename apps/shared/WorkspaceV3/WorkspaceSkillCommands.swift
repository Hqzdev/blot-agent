import BlotDomain
import BlotWorkspace
import Foundation

@MainActor
protocol WorkspaceSkillCommands: WorkspaceObservationService {
    func saveSkill(id: UUID?, version: Int, name: String, instructions: String, parameters: [SkillParameter], tools: [String]) async throws -> UUID
    func archiveSkill(_ skill: BlotV3.Skill, archived: Bool) async throws
    func activateSkill(_ skill: BlotV3.Skill, revisionID: UUID) async throws
    func assignSkill(_ skillID: UUID, agentID: UUID, assigned: Bool, version: Int) async throws
    func runSkill(_ skillID: UUID, revisionID: UUID, agentID: UUID, values: [String: String], conversationID: UUID?) async throws -> UUID
    func renderSkill(_ revisionID: UUID, values: [String: String]) async throws -> String
}
@MainActor
protocol WorkspaceSkillProviding { var workspaceSkills: (any WorkspaceSkillCommands)? { get } }

enum WorkspaceSkillFailure {
    static func text(_ error: Error, russian: Bool) -> String {
        switch error {
        case WorkspaceSkillError.invalidTemplate: return russian ? "Проверьте {{параметры}} в инструкции: каждый должен быть объявлен ниже." : "Every {{parameter}} in the instructions must be declared below."
        case WorkspaceSkillError.notAssigned: return russian ? "Сначала назначьте навык этому агенту." : "Assign the skill to this agent first."
        case WorkspaceSkillError.toolsUnavailable: return russian ? "Агенту недоступны некоторые инструменты навыка. Измените инструменты или права агента." : "Some skill tools are unavailable to this agent. Update the skill tools or agent permissions."
        case WorkspaceSkillError.archived: return russian ? "Сначала восстановите навык из архива." : "Restore the skill from the archive first."
        case WorkspaceStorageError.versionConflict: return russian ? "Навык изменён на другом устройстве. Откройте его заново." : "The skill changed on another device. Reopen it."
        case WorkspaceStorageError.invalidParameters: return russian ? "Проверьте поля и обязательные параметры. Имена параметров: латинские буквы, цифры и _." : "Check the fields and required parameters. Parameter names use letters, digits and _."
        default: return russian ? "Не удалось сохранить или запустить навык. Обновите страницу и повторите." : "Could not save or run the skill. Refresh and try again."
        }
    }
}
