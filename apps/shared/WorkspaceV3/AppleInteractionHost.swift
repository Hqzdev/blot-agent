import BlotAppleIntegrations
import BlotDesign
import BlotWorkspace
import SwiftUI
#if os(iOS)
import MessageUI
#endif

struct AppleInteractionHost: ViewModifier {
    let center: AppleInteractionCenter?
    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { center?.pending }, set: { value in
            if value == nil, let center, let pending = center.pending {
                center.finish(pending.id, result: .failure(AppleIntegrationError.canceled))
            }
        })) { interaction in
            if let center {
                #if os(iOS)
                if interaction.kind == .mail { AppleMailComposer(interaction: interaction, center: center) }
                else { confirmation(interaction, center: center) }
                #else
                confirmation(interaction, center: center)
                #endif
            }
        }
    }
    private func confirmation(_ interaction: AppleInteraction, center: AppleInteractionCenter) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(interaction.title).font(.headline)
            ScrollView { Text(interaction.details).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            HStack {
                Button("Отмена", role: .cancel) { center.finish(interaction.id, result: .success(.bool(false))) }
                Spacer()
                Button("Разрешить один раз") { center.finish(interaction.id, result: .success(.bool(true))) }
                    .buttonStyle(WorkspaceButtonStyle())
            }
        }.padding(24)
        #if os(macOS)
        .frame(width: 580, height: 480)
        #endif
        .interactiveDismissDisabled()
    }
}

#if os(iOS)
private struct AppleMailComposer: UIViewControllerRepresentable {
    let interaction: AppleInteraction
    let center: AppleInteractionCenter
    func makeCoordinator() -> Coordinator { Coordinator(interaction: interaction, center: center) }
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([interaction.fields["recipient"] ?? ""])
        controller.setSubject(interaction.fields["subject"] ?? "")
        controller.setMessageBody(interaction.fields["body"] ?? "", isHTML: false)
        return controller
    }
    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}
    @MainActor final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let interaction: AppleInteraction
        let center: AppleInteractionCenter
        init(interaction: AppleInteraction, center: AppleInteractionCenter) { self.interaction = interaction; self.center = center }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            if let error { center.finish(interaction.id, result: .failure(error)); return }
            let state: String
            switch result { case .sent: state = "submitted_to_mail"; case .saved: state = "draft_saved"; case .cancelled: state = "canceled"; default: state = "failed" }
            center.finish(interaction.id, result: .success(.object(["state": .string(state), "delivery_confirmed": .bool(false)])))
        }
    }
}
#endif
