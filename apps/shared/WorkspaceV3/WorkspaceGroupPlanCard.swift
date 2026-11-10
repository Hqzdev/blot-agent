import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

struct WorkspaceGroupPlanCard: View {
    let plan: WorkspaceGroupPlanProgress
    let agents: [BlotV3.AgentProfile]
    var skills: [BlotV3.Skill] = []
    var russian = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "list.bullet.rectangle").foregroundStyle(.secondary)
                Text(russian ? "План работы" : "Work plan").font(.headline)
                Spacer(minLength: 12)
                Text("\(plan.completedCount)/\(plan.steps.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if !plan.summary.isEmpty {
                WorkspaceMessageText(text: plan.summary, agents: agents, skills: skills).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: step.completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21)).foregroundStyle(step.completed ? Color.green : .secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            if let agent = agents.first(where: { $0.metadata.id == step.agentID || $0.name == step.name }) {
                                WorkspaceAvatar(shape: .init(rawValue: agent.avatarShape) ?? .round,
                                    color: WorkspaceAvatarPalette.color(agent.avatarColor), size: 18)
                                Text(step.name).foregroundStyle(WorkspaceAvatarPalette.color(agent.avatarColor))
                            } else { Text(step.name).foregroundStyle(.secondary) }
                        }.font(.caption.weight(.semibold))
                        WorkspaceMessageText(text: step.task, agents: agents, skills: skills)
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(step.completed ? (russian ? "Выполнено" : "Completed") : (russian ? "Не завершено" : "Not completed"))
                if index < plan.steps.count - 1 { Divider().padding(.leading, 33) }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkspaceStyle.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(WorkspaceStyle.secondary.opacity(0.16)))
        .accessibilityIdentifier("workspace.chat.plan-card")
    }
}
