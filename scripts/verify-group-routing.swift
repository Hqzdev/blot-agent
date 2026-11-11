import BlotDomain
import BlotWorkspace
import Foundation

private actor ScriptedGroupModel: ChatModel {
    let scenario: String
    let ids: [UUID]
    var routingCalls = 0
    var leakedOldTask = false
    var conclusionUsesCurrentEvidence = false
    var workersReceiveOwnAssignment = true
    init(_ scenario: String, ids: [UUID]) { self.scenario = scenario; self.ids = ids }
    nonisolated func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            _Concurrency.Task {
                for event in await self.events(request) { continuation.yield(event) }
                continuation.finish()
            }
        }
    }
    private func events(_ request: ChatModelRequest) -> [ChatModelEvent] {
        let systems = request.messages.filter { $0.role == "system" }.map(\.content).joined(separator: "\n")
        if systems.contains("ordinary group conversation"), request.messages.contains(where: { $0.content.contains("OLD_CALENDAR_TASK") }) { leakedOldTask = true }
        let text: String
        if systems.contains("Select the interaction mode") {
            routingCalls += 1
            if scenario == "social-routing" { text = "{\"mode\":\"conversation\"}" }
            else if scenario == "conversation-tool" || scenario == "repaired-tool-route" {
                text = scenario == "repaired-tool-route" && routingCalls == 1 ? "Invalid routing object." : "{\"mode\":\"conversation\",\"firstToolID\":\"document_create\"}"
            }
            else if scenario == "specialist" { text = "{\"mode\":\"specialist\",\"agentID\":\"\(ids[1])\"}" }
            else if scenario == "malformed" { text = "I can answer directly." }
            else { text = "{\"mode\":\"team\",\"summary\":\"Анализ и таблица\",\"assignments\":[{\"agentID\":\"\(ids[1])\",\"task\":\"Analyze the data\"},{\"agentID\":\"\(ids[2])\",\"task\":\"Create a Markdown table\",\"dependsOn\":[\"\(ids[1])\"]}]}" }
        } else if scenario == "conversation-tool" || scenario == "repaired-tool-route" {
            precondition(request.tools.contains { $0.name == "document_create" }, "A non-casual conversation route must retain permitted file tools")
            if request.messages.last?.role == "tool" {
                precondition(request.requiredTool == nil, "Continuation must return to automatic selection")
                return [.text("Документ создан."), .finished(.stop)]
            }
            precondition(request.requiredTool == "document_create", "The selected first tool must reach the provider request")
            return [.text("Создам тестовый документ."), .toolCall(.init(id: "conversation-document", name: "document_create", arguments: .object(["name": .string("Conversation check"), "format": .string("markdown"), "content": .string("Actual file")] ))), .finished(.toolCalls)]
        } else if systems.contains("Rewrite each assigned task") {
            text = "{\"summary\":\"Work plan\",\"assignments\":[{\"agentID\":\"\(ids[1])\",\"task\":\"I will analyze the data.\"},{\"agentID\":\"\(ids[2])\",\"task\":\"I will create a Markdown table.\"}]}"
        } else if systems.contains("Verify completion of one assigned step") {
            let manager = request.messages.last?.content.contains("Create a Markdown table") == true
            let completed = !(scenario == "blocked" && manager)
            text = "{\"summary\":\"\(manager ? "I created the table." : "I analyzed the data.")\",\"completed\":\(completed)}"
        } else if systems.contains("Return JSON {\"summary\"") {
            conclusionUsesCurrentEvidence = request.messages.last?.content.contains("Actual discussion this turn") == true
                && request.messages.last?.content.contains("выручка 10") == true
            if scenario == "broken-conclusion" { text = "{\"summary\":\"broken" }
            else if scenario == "nested-conclusion" { text = #"{"summary":"{\"summary\":\"Готово.\",\"completed\":true}","completed":true}"# }
            else { text = "{\"summary\":\"Анализ выполнен, таблица создана\",\"completed\":\(scenario == "blocked" ? "false" : "true")}" }
        } else if systems.contains("You are Analyst, working") {
            workersReceiveOwnAssignment = workersReceiveOwnAssignment && request.messages.last?.content.contains("Your active assignment as Analyst:") == true
            text = "@Manager, анализ готов: выручка 10, расходы 4, прибыль 6."
        } else if systems.contains("You are Manager, working") {
            if request.messages.last?.role != "tool" {
                workersReceiveOwnAssignment = workersReceiveOwnAssignment && request.messages.last?.content.contains("Your active assignment as Manager:") == true
            }
            if request.messages.last?.role == "tool" { text = "Таблица создана по данным @Analyst." }
            else {
                return [.toolCall(.init(id: UUID().uuidString, name: "document_create", arguments: .object([
                    "name": .string("Analysis table"), "format": .string("markdown"),
                    "content": .string("|Metric|Value|\n|---|---|\n|Revenue|10|\n|Profit|6|")]))), .finished(.toolCalls)]
            }
        } else { text = systems.contains("ordinary group conversation") ? "Привет! Всё хорошо." : "Самостоятельный ответ специалиста." }
        if systems.contains("Select the interaction mode"), scenario != "malformed", !(scenario == "repaired-tool-route" && routingCalls == 1) {
            precondition(request.requiredTool == "select_group_route" && request.tools.count == 1)
            let arguments = try! JSONDecoder().decode(ChatJSON.self, from: Data(text.utf8))
            return [.toolCall(.init(id: "routing", name: "select_group_route", arguments: arguments)), .finished(.toolCalls)]
        }
        return [.text(text), .finished(.stop)]
    }
}

@main struct VerifyGroupRouting {
    @MainActor static func main() async throws {
        for scenario in ["greeting", "social-routing", "conversation-tool", "repaired-tool-route", "specialist", "team", "addressed", "blocked", "malformed", "nested-conclusion", "broken-conclusion"] { try await verify(scenario) }
        print("PASS: real group pipeline — ownership, team tools, pin lifecycle, bounded routing repair and rejection without false-success fallback")
    }
    @MainActor static func verify(_ scenario: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try WorkspaceRepository(url: directory.appendingPathComponent("db.sqlite"))
        let identity = try await repository.localIdentity()
        let agents = WorkspaceAgentService(repository: repository, identity: identity)
        var ids: [UUID] = []
        for name in ["CEO", "Analyst", "Manager"] {
            ids.append(try await agents.save(commandID: UUID(), draft: .init(name: name, instructions: "Work as " + name,
                modelID: "gigachat", toolIDs: name == "Manager" || (["conversation-tool", "repaired-tool-route"].contains(scenario) && name == "CEO") ? ["document_create"] : [])))
        }
        let group = try await WorkspaceGroupService(repository: repository, identity: identity).create(commandID: UUID(), title: "Team", agentIDs: ids)
        if scenario == "greeting" {
            let oldID = try await WorkspaceChatService(repository: repository, identity: identity).sendMessage(commandID: UUID(), conversationID: group, content: "OLD_CALENDAR_TASK")
            let oldSource = try await repository.record(BlotV3.Message.self, id: oldID, workspaceID: identity.workspaceID)!
            let recorder = WorkspaceResponseRecorder(repository: repository, identity: identity)
            let oldReply = try await recorder.begin(id: UUID(), replyingTo: oldSource, agentID: ids[0])
            _ = try await recorder.finish(oldReply.metadata.id, delivery: .completed, content: "[CEO] OLD_CALENDAR_TASK created successfully")
        }
        let sourceID = try await WorkspaceChatService(repository: repository, identity: identity).sendMessage(commandID: UUID(), conversationID: group,
            content: scenario == "greeting" ? "Привет" : scenario == "social-routing" ? "Как настроение у команды?"
                : ["conversation-tool", "repaired-tool-route", "malformed"].contains(scenario) ? "Создай тестовый документ" : scenario == "specialist" ? "Проанализируй данные"
                : scenario == "addressed" ? "Analyst — Analyze the data. Manager — Create a Markdown table using Analyst's results." : "Проанализируй данные и подготовь таблицу")
        let source = try await repository.record(BlotV3.Message.self, id: sourceID, workspaceID: identity.workspaceID)!
        let model = ScriptedGroupModel(scenario, ids: ids)
        let service = try LocalWorkspaceService(databaseURL: directory.appendingPathComponent("db.sqlite"), repository: repository,
            identity: identity, makeModel: { _ in model })
        _ = try await service.load()
        var sawPlan = false, sawPartialPlan = false
        let stream = try await service.responses(to: source)
        var rejectedConclusion = false
        do {
            for try await _ in stream {
                if let id = try await repository.pinnedGroupPlans()[group] {
                    sawPlan = true
                    if let saved = try await repository.record(BlotV3.Message.self, id: id, workspaceID: identity.workspaceID),
                       let plan = WorkspaceGroupPlanProgress.decode(saved.content), plan.completedCount > 0 && !plan.allCompleted { sawPartialPlan = true }
                }
            }
        } catch {
            if scenario == "malformed", error as? WorkspaceGroupResponseError == .invalidPlan {
                let projection = try await repository.projection(identity: identity)
                let calls = await model.routingCalls
                precondition(calls == 2, "Only one repair is allowed")
                precondition(projection.artifacts.isEmpty && !projection.messages.contains { $0.role == .assistant && $0.delivery == .completed })
                precondition(projection.modelSteps.allSatisfy { $0.toolCallsJSON == nil }, "No workspace operation follows invalid routing")
                try await service.close()
                print("PASS: invalid route cannot fall back to a simulated-success response")
                return
            }
            guard scenario == "broken-conclusion", error is WorkspaceGroupConclusion.Failure else { throw error }
            rejectedConclusion = true
        }
        precondition(rejectedConclusion == (scenario == "broken-conclusion"))
        let projection = try await repository.projection(identity: identity)
        let replies = projection.messages.filter { $0.role == .assistant && $0.delivery == .completed && (!$0.content.isEmpty || !$0.artifactIds.isEmpty) && $0.commandId == source.commandId }
        precondition(!replies.contains { $0.content.contains("\"summary\":") || $0.content.contains("\"completed\":") })
        let pins = try await repository.pinnedGroupPlans()
        let routingCalls = await model.routingCalls
        let leakedOldTask = await model.leakedOldTask
        precondition(!leakedOldTask, "A greeting must not receive historical work or success claims")
        switch scenario {
        case "greeting", "social-routing":
            precondition(replies.count == 1 && replies[0].authorAgentId == ids[0])
            precondition(routingCalls == (scenario == "greeting" ? 0 : 1) && !sawPlan && pins.isEmpty)
        case "conversation-tool", "repaired-tool-route":
            precondition(replies.count == 2 && replies.allSatisfy { $0.authorAgentId == ids[0] } && !sawPlan)
            precondition(routingCalls == (scenario == "repaired-tool-route" ? 2 : 1))
            precondition(projection.artifacts.count == 1 && projection.modelSteps.contains { $0.toolCallsJSON?.contains("document_create") == true && $0.toolResultsJSON != nil })
        case "specialist": precondition(replies.count == 1 && replies[0].authorAgentId == ids[1] && !sawPlan)
        case "team", "addressed", "blocked", "nested-conclusion", "broken-conclusion":
            precondition(sawPlan)
            precondition(sawPartialPlan, "Plan checkmarks must update as individual steps finish")
            let planMessage = replies.first { WorkspaceGroupPlanProgress.decode($0.content) != nil }!
            let progress = WorkspaceGroupPlanProgress.decode(planMessage.content)!
            precondition(progress.allCompleted == (scenario != "blocked"), "\(scenario): \(progress.markdown) states=\(projection.modelSteps.map { String(describing: $0.state) })")
            precondition(progress.steps.allSatisfy { WorkspaceGroupPlanPresenter.isFirstPerson($0.task) })
            let usesEvidence = await model.conclusionUsesCurrentEvidence
            precondition(usesEvidence, "Conclusions must receive actual current replies as the final input")
            let receivesAssignment = await model.workersReceiveOwnAssignment
            precondition(receivesAssignment, "Workers must receive their own current assignment as the final user input")
            if scenario == "addressed" { precondition(routingCalls == 0, "Explicitly named owners must not be reassigned by a planner") }
            precondition((["team", "addressed", "nested-conclusion"].contains(scenario)) == pins.isEmpty)
            precondition(projection.artifacts.count == 1)
            precondition(replies.contains { ($0.mentions ?? []).contains { $0.agentId == ids[2] } })
            precondition(replies.contains { message in
                message.authorAgentId == ids[2] && projection.messages.contains { $0.metadata.id == message.replyToMessageId && $0.authorAgentId == ids[1] }
            })
        default: precondition(replies.count == 1 && replies[0].authorAgentId == ids[0] && !sawPlan)
        }
        try await service.close()
        print("PASS:", scenario)
    }
}
