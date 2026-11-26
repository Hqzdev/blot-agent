import BlotDesign
import SwiftUI

/// Application confirmations use the same opaque surfaces as editors. OS permission
/// prompts and document pickers remain owned by the operating system.
extension View {
    func workspaceConfirmationDialog<Actions: View, Message: View>(_ title: String, isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic, @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder message: @escaping () -> Message) -> some View {
        sheet(isPresented: isPresented) {
            WorkspaceConfirmationPanel(title: title, isPresented: isPresented, actions: actions, message: message)
        }
    }
    func workspaceConfirmationDialog<Actions: View>(_ title: String, isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic, @ViewBuilder actions: @escaping () -> Actions) -> some View {
        workspaceConfirmationDialog(title, isPresented: isPresented, actions: actions, message: { EmptyView() })
    }
    func workspaceConfirmationDialog<Data, Actions: View, Message: View>(_ title: String, isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic, presenting data: Data?, @ViewBuilder actions: @escaping (Data) -> Actions,
        @ViewBuilder message: @escaping (Data) -> Message) -> some View {
        sheet(isPresented: isPresented) {
            if let data {
                WorkspaceConfirmationPanel(title: title, isPresented: isPresented, actions: { actions(data) }, message: { message(data) })
            }
        }
    }
    func workspaceConfirmationDialog<Data, Actions: View>(_ title: String, isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic, presenting data: Data?, @ViewBuilder actions: @escaping (Data) -> Actions) -> some View {
        workspaceConfirmationDialog(title, isPresented: isPresented, presenting: data, actions: actions, message: { _ in EmptyView() })
    }
}

private struct WorkspaceConfirmationPanel<Actions: View, Message: View>: View {
    let title: String
    @Binding var isPresented: Bool
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let message: () -> Message
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                Text(title).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button { isPresented = false } label: { BlotIcon(.close, size: 18).frame(width: 36, height: 36) }
                    .buttonStyle(BlotPlainButtonStyle(showsHover: false)).blotRow().keyboardShortcut(.cancelAction)
                    .accessibilityLabel(Text("Close"))
            }
            message().foregroundStyle(WorkspaceStyle.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10, content: actions)
                .buttonStyle(WorkspaceConfirmationActionStyle { isPresented = false })
        }.padding(24).frame(idealWidth: 440).workspacePanelControls()
            .background(WorkspaceStyle.canvas).presentationBackground(WorkspaceStyle.canvas).presentationCornerRadius(28)
    }
}

/// Trigger before dismissal: actions may depend on the selected record in the binding.
private struct WorkspaceConfirmationActionStyle: PrimitiveButtonStyle {
    let close: () -> Void
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) { configuration.trigger(); close() } label: {
            configuration.label.frame(maxWidth: .infinity)
        }.buttonStyle(BlotButtonStyle(configuration.role == .destructive ? .destructive : configuration.role == .cancel ? .ghost : .primary, size: .large))
    }
}
