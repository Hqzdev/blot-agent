import BlotAPI
import BlotDesign
import SwiftUI

struct PhoneRootView: View {
    @State private var connection = PhoneConnection()
    @State private var code = ""
    @State private var bluetooth = false
    @State private var scanner = false
    var body: some View {
        Group {
            if let client = connection.client {
                PhoneWorkspaceView(client: client, disconnect: connection.disconnect)
            } else {
                NavigationStack {
                    Form {
                        Section {
                            VStack(alignment: .leading, spacing: BlotSpace.s10) {
                                Text("Connect to your Mac").blotFont(.heading).foregroundStyle(BlotColor.text)
                                    .accessibilityAddTraits(.isHeader)
                                Text("Open Blot on your Mac, choose Devices → Connect iPhone, then scan the QR code.")
                                    .blotFont(.body).foregroundStyle(BlotColor.textSecondary)
                            }
                            .padding(.vertical, BlotSpace.element)
                        }
                        .phoneRow()
                        Section {
                            BlotStatusLabel(connection.status, status: .info, role: .body)
                            Toggle("Use Bluetooth", isOn: $bluetooth)
                                .blotFont(.body)
                                .frame(minHeight: BlotLayout.minimumTapTarget)
                            Button { scanner = true } label: { Label("Scan QR code", systemImage: "qrcode.viewfinder") }
                                .buttonStyle(PhoneButtonStyle(kind: .primary, fullWidth: true))
                            Button { Task { await connection.restore(bluetooth: bluetooth) } } label: {
                                Label("Reconnect saved Mac", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(PhoneButtonStyle(fullWidth: true))
                        } header: { PhoneSectionHeader("Connection") }
                        .phoneRow()
                        Section {
                            TextField("Paste the code from your Mac", text: $code, axis: .vertical)
                                .blotFont(.code)
                                .lineLimit(3...6)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .accessibilityLabel("Connection code")
                            Button("Connect") { connection.pair(json: code, bluetooth: bluetooth) }
                                .buttonStyle(PhoneButtonStyle(fullWidth: true))
                                .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        } header: { PhoneSectionHeader("Connection code") }
                        .phoneRow()
                        if let error = connection.error {
                            Section { PhoneErrorText(error) } header: { PhoneSectionHeader("Couldn’t connect") }
                                .phoneRow()
                        }
                    }
                    .phoneList()
                    .navigationTitle("Blot")
                }
            }
        }
        .task { await connection.restore() }
        .sheet(isPresented: $scanner) {
            NavigationStack {
                PhoneQRScanner { value in code = value; scanner = false; connection.pair(json: value, bluetooth: bluetooth) }
                    .navigationTitle("Scan connection code")
                    .phoneBars()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { scanner = false } }
                    }
            }
        }
    }
}
