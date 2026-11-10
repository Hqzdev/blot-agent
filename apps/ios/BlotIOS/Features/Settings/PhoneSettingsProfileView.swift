import BlotDomain
import BlotDesign
import SwiftUI

struct PhoneSettingsProfileView: View {
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        let activity = PhoneSettingsActivity(snapshot: store.snapshot)
        PhoneSettingsPage {
            PhoneProfileIdentitySection()
            PhoneSettingsGroup(title: "Activity") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 16)], spacing: 24) {
                    metric("Total tokens", value: activity.totalTokens)
                    metric("Peak per call", value: activity.peakTokens)
                    metric("Model calls", value: activity.calls)
                    metric("Active days", value: activity.activeDays)
                }.padding(20)
            }
            PhoneSettingsGroup(title: "Your team") {
                if store.snapshot.agents.isEmpty {
                    VStack(spacing: 14) {
                        Text(store.settingsText("Add the first specialist to your team")).font(.subheadline).foregroundStyle(.secondary)
                        Button(store.t("Create agent")) { store.beginAgentCreation() }.buttonStyle(.bordered)
                    }.frame(maxWidth: .infinity).padding(20)
                } else {
                    ForEach(Array(store.snapshot.agents.enumerated()), id: \.element.metadata.id) { index, agent in
                        if index > 0 { PhoneSettingsDivider() }
                        Button { store.selectAgent(agent.metadata.id, destination: .editAgent) } label: {
                            HStack(spacing: 14) {
                                WorkspaceAvatarView(agent: agent, size: 40)
                                Text(agent.name).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                                BlotIcon(.chevronRight, size: 11).foregroundStyle(.secondary)
                            }.padding(16).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            PhoneSettingsTokenHeatmap(dailyTokens: activity.dailyTokens)
            PhoneSettingsGroup(title: "By model") {
                if activity.models.isEmpty { PhoneSettingsRow(title: "No model calls yet", showsChevron: false) }
                ForEach(Array(activity.models.enumerated()), id: \.element.id) { index, model in
                    if index > 0 { PhoneSettingsDivider() }
                    PhoneSettingsRow(title: model.id, detail: store.settingsText("Model calls") + ": " + model.calls.formatted(), value: model.tokens.formatted(), showsChevron: false)
                }
            }
            PhoneSettingsGroup(title: "Model usage", detail: "Counters use the data returned by the provider.") {
                PhoneSettingsRow(title: "Incoming", detail: "Instructions, history and model requests.", value: activity.inputTokens.formatted(), showsChevron: false)
                PhoneSettingsDivider()
                PhoneSettingsRow(title: "Outgoing", detail: "Model responses.", value: activity.outputTokens.formatted(), showsChevron: false)
                if activity.uncountedCalls > 0 {
                    PhoneSettingsDivider()
                    PhoneSettingsRow(title: "No token data", detail: "The exact usage of these calls is unknown.", value: activity.uncountedCalls.formatted(), showsChevron: false)
                }
            }
            PhoneSettingsGroup(title: "Your workspace") {
                PhoneSettingsRow(title: "Workspace", value: store.settingsText("Personal workspace"), showsChevron: false)
                PhoneSettingsDivider()
                PhoneSettingsRow(title: "Connected accounts", value: store.snapshot.connections.count.formatted(), showsChevron: false)
            }
            PhoneProfileDangerZone()
            WorkspaceFeedback()
        }
    }
    private func metric(_ title: String, value: Int) -> some View {
        VStack(spacing: 7) {
            Text(value, format: .number.notation(.compactName)).font(.title3.weight(.medium)).monospacedDigit()
            Text(store.settingsText(title)).font(.footnote).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}
