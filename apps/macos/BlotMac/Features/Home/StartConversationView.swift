import BlotDesign
import SwiftUI

/// The first screen is a conversation entry point, independent of repositories.
struct StartConversationView: View {
    @Environment(AppState.self) private var app
    @State private var creatingProject = false

    var body: some View {
        @Bindable var app = app
        VStack(spacing: KSpace.xl) {
            Spacer(minLength: KSpace.xl)
            VStack(spacing: KSpace.md) {
                PrimaryBlot(context: .workHome)
                Text("С чего начнём?")
                    .font(KFont.pageTitle()).foregroundStyle(K.text)
                    .accessibilityAddTraits(.isHeader)
                Text("Задайте вопрос или соберите всё нужное в проекте.")
                    .font(KFont.body()).foregroundStyle(K.text2)
                    .multilineTextAlignment(.center)
            }
            ContentColumn {
                Composer(text: $app.workChatDraft, placeholder: "Напишите Blot…", showsModel: false) {
                    app.sendWorkChatMessage()
                }
            }
            KButton(title: "Создать проект", icon: "folder.badge.plus", height: K.controlHeightLarge) {
                creatingProject = true
            }
            Spacer(minLength: KSpace.section)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, KSpace.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $creatingProject) { ProjectCreationView() }
    }
}
