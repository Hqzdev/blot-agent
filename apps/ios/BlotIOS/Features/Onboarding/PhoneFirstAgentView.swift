import BlotDesign
import SwiftUI

private struct PhoneFirstAgentTemplate: Identifiable {
    let name: String
    let instructions: String
    let shape: WorkspaceAvatar.ShapeKind
    let color: String
    var id: String { name }

    static let all: [Self] = [
        .init(name: "Chief of Staff", instructions: "Reads tomorrow’s calendar, preps a morning digest", shape: .drop, color: "orange"),
        .init(name: "Meal planner", instructions: "Plans the week’s meals and builds your shopping list", shape: .triangle, color: "green"),
        .init(name: "UX Research", instructions: "Challenges assumptions and finds evidence.", shape: .pill, color: "amber"),
        .init(name: "Design", instructions: "Proposes UI and checks the details.", shape: .round, color: "ink"),
        .init(name: "Inbox Triage", instructions: "Organizes email and prepares replies.", shape: .square, color: "gray")
    ]
}

struct PhoneFirstAgentView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var selectedIndex = 0

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("blot.v3.reduceMotion") private var reduceMotion = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 22) {
                    Text(store.t("Meet your first agent"))
                        .font(.system(size: 26, weight: .semibold))
                        .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 24).padding(.top, 84)
                    TabView(selection: $selectedIndex) {
                        ForEach(Array(PhoneFirstAgentTemplate.all.enumerated()), id: \.element.id) { index, template in
                            VStack(spacing: 18) {
                                Spacer(minLength: 28)
                                PhoneAgentPreview(shape: template.shape, color: template.color, size: 156)
                                Spacer(minLength: 32)
                                Text(store.t(template.name)).font(.title2.weight(.semibold))
                                Text(store.t(template.instructions)).font(.subheadline)
                                    .foregroundStyle(WorkspaceStyle.secondary).multilineTextAlignment(.center)
                                    .padding(.horizontal, 32).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 28)
                            }.tag(index)
                        }
                    }.tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(height: max(390, geometry.size.height - 140))
                }.frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
            }.scrollBounceBehavior(.basedOnSize)
                .overlay(alignment: .topTrailing) { menu.padding(.trailing, 18).padding(.top, 6) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .sensoryFeedback(.selection, trigger: selectedIndex)
    }

    private var menu: some View {
        Menu {
            Button(store.t("Create my own")) { store.beginAgentCreation() }
            Button(store.t("Settings")) { store.navigate(.settings) }
        } label: {
            BlotIcon(symbol: "ellipsis").font(.title3)
                .frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: .circle)
        }.accessibilityLabel(store.t("More options"))
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(PhoneFirstAgentTemplate.all.indices, id: \.self) { index in
                    Button {
                        withAnimation(systemReduceMotion || reduceMotion ? nil : .easeInOut(duration: 0.25)) { selectedIndex = index }
                    } label: {
                        Circle().fill(index == selectedIndex ? WorkspaceStyle.secondary : WorkspaceStyle.secondary.opacity(0.18))
                            .frame(width: 6, height: 6).frame(width: 22, height: 30)
                    }.buttonStyle(.plain)
                        .accessibilityLabel(store.t(PhoneFirstAgentTemplate.all[index].name))
                        .accessibilityAddTraits(index == selectedIndex ? .isSelected : [])
                }
            }
            Button { startChat() } label: {
                Text(store.t("Start chat")).font(.headline).frame(maxWidth: .infinity, minHeight: 24)
            }.buttonStyle(WorkspaceButtonStyle()).disabled(store.busy)
            Button(store.t("Create my own")) { store.beginAgentCreation() }
                .font(.title3).foregroundStyle(WorkspaceStyle.secondary)
                .frame(minHeight: 44).buttonStyle(.plain)
            WorkspaceFeedback()
        }.padding(.horizontal, 30).padding(.bottom, 20)
    }

    private func startChat() {
        let template = PhoneFirstAgentTemplate.all[selectedIndex]
        store.form.agent.name = store.t(template.name)
        store.form.agent.instructions = store.t(template.instructions)
        store.form.agent.shape = template.shape.rawValue
        store.form.agent.color = template.color
        _Concurrency.Task { await store.createAgentAndStartChat() }
    }
}
