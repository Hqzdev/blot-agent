import SwiftUI

extension EnvironmentValues {
    @Entry var workspacePanelDismiss: WorkspacePanelDismissAction? = nil
}

nonisolated struct WorkspacePanelDismissAction: Equatable {
    let id: UUID
    let perform: @MainActor () -> Void
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    @MainActor func callAsFunction() { perform() }
}

@propertyWrapper struct WorkspacePresentationDismiss: DynamicProperty {
    @Environment(\.dismiss) private var nativeDismiss
    @Environment(\.workspacePanelDismiss) private var panelDismiss
    var wrappedValue: () -> Void { { if let panelDismiss { panelDismiss() } else { nativeDismiss() } } }
}

/// Tool details use the pane's navigation stack; standalone screens retain their normal sheets.
extension View {
    func workspacePanelSheet<Item: Identifiable, Destination: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Destination) -> some View {
        modifier(WorkspacePanelItemPresentation(item: item, onDismiss: onDismiss, destination: content))
    }
    func workspacePanelSheet<Destination: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Destination) -> some View {
        modifier(WorkspacePanelPresentation(isPresented: isPresented, onDismiss: onDismiss, destination: content))
    }
}

private struct WorkspacePanelItemPresentation<Item: Identifiable, Destination: View>: ViewModifier {
    @Binding var item: Item?
    let onDismiss: (() -> Void)?
    let destination: (Item) -> Destination
    @State private var dismissalID = UUID()
    @Environment(\.workspacePanelNavigation) private var panel
    func body(content: Content) -> some View {
        if panel != nil {
            content.navigationDestination(isPresented: Binding(get: { item != nil }, set: { shown in
                if !shown, item != nil { item = nil; onDismiss?() }
            })) {
                if let item {
                    destination(item).environment(\.workspacePanelDismiss, .init(id: dismissalID, perform: { close() })).workspacePanelDetailChrome()
                        .onAppear { panel?.dismissDetail = .init(id: dismissalID, perform: { close() }) }.onDisappear { panel?.dismissDetail = nil }
                }
            }
        } else { content.sheet(item: $item, onDismiss: onDismiss, content: destination) }
    }
    private func close() { guard item != nil else { return }; item = nil; onDismiss?() }
}

private struct WorkspacePanelPresentation<Destination: View>: ViewModifier {
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    let destination: () -> Destination
    @State private var dismissalID = UUID()
    @Environment(\.workspacePanelNavigation) private var panel
    func body(content: Content) -> some View {
        if panel != nil {
            content.navigationDestination(isPresented: Binding(get: { isPresented }, set: { shown in
                let dismissed = isPresented && !shown; isPresented = shown
                if dismissed { onDismiss?() }
            })) {
                destination().environment(\.workspacePanelDismiss, .init(id: dismissalID, perform: { close() })).workspacePanelDetailChrome()
                    .onAppear { panel?.dismissDetail = .init(id: dismissalID, perform: { close() }) }.onDisappear { panel?.dismissDetail = nil }
            }
        } else { content.sheet(isPresented: $isPresented, onDismiss: onDismiss, content: destination) }
    }
    private func close() { guard isPresented else { return }; isPresented = false; onDismiss?() }
}

private extension View {
    @ViewBuilder func workspacePanelDetailChrome() -> some View {
        #if os(macOS)
        self.navigationBarBackButtonHidden(true).toolbarVisibility(.hidden, for: .windowToolbar)
        #else
        self.navigationBarBackButtonHidden(true)
        #endif
    }
}

/// Form controls remain reachable when the window toolbar belongs to the chat.
struct WorkspacePanelFormHeader<Actions: View>: View {
    let title: String
    @ViewBuilder let actions: () -> Actions
    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Text(title).font(.headline).lineLimit(1).fixedSize()
                    Spacer(minLength: 0)
                    HStack(spacing: 8, content: actions).fixedSize()
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).font(.headline)
                    HStack { Spacer(minLength: 0); HStack(spacing: 8, content: actions).fixedSize() }
                }
            }.padding(14)
            Divider()
        }
    }
}
