import BlotDesign
import SwiftUI
import AppKit
import Virtualization
import UniformTypeIdentifiers

struct VirtualMachineSettingsView: View {
    @State private var preparation = VirtualMachinePreparation.shared
    @State private var error: String?
    private let guestCommand = "sudo sh '/Volumes/My Shared Files/bootstrap/install-guest.sh'"

    var body: some View {
        SettingsGroup(title: "macOS runtime",
                      detail: "Commands run in a separate virtual machine: 4 CPUs, 8 GB of memory, up to 128 GB of disk. Jobs have no network access.") {
            SettingsRow(title: "1 · Install macOS", detail: "Choose a macOS IPSW image to create the base machine.") {
                KButton(title: "Choose IPSW…", icon: "file-text") { chooseImage() }
                    .disabled(preparation.isBusy || preparation.machine != nil)
            }
            SettingsDivider()
            SettingsRow(title: "2 · Prepare tools", detail: "Starts the guest so you can install the runner, JDK 25, Xcode and project dependencies.") {
                KButton(title: "Start preparation", icon: "play") { perform { try await preparation.prepare() } }
                    .disabled(preparation.isBusy || preparation.machine != nil)
            }
            SettingsDivider()
            SettingsRow(title: "3 · Save the image", detail: "Shut down the guest first. Jobs start from this saved image.") {
                KButton(title: "Save image", icon: "check", kind: .primary) { perform { try await preparation.seal() } }
                    .disabled(preparation.machine == nil || preparation.isBusy)
            }
            if preparation.isBusy || !preparation.message.isEmpty || error != nil {
                SettingsDivider()
                GroupContent {
                    if preparation.isBusy { LoadingState(label: preparation.message.isEmpty ? "Working…" : preparation.message) }
                    else if !preparation.message.isEmpty { InlineFeedback(text: preparation.message, tone: .information) }
                    if let error { InlineFeedback(text: error, tone: .error) }
                }
            }
        }
        SettingsGroup(title: "In the guest macOS",
                      detail: "Open Terminal in the guest and run the command below. Do not sign in to personal accounts. Close apps and files before saving.") {
            GroupContent {
                CodeBlock(title: "Terminal", icon: "terminal", text: guestCommand, maxHeight: nil)
            }
        }
        if let machine = preparation.machine {
            SettingsGroup(title: "Guest screen") {
                GuestScreen(machine: machine).frame(minWidth: 640, minHeight: 420)
            }
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ipsw") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform { try await preparation.install(from: url) }
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        error = nil
        _Concurrency.Task { do { try await action() } catch { self.error = error.localizedDescription } }
    }
}
private struct GuestScreen: NSViewRepresentable {
    let machine: VZVirtualMachine
    func makeNSView(context: Context) -> VZVirtualMachineView { let view = VZVirtualMachineView(); view.virtualMachine = machine; view.capturesSystemKeys = true; return view }
    func updateNSView(_ view: VZVirtualMachineView, context: Context) { view.virtualMachine = machine }
}
