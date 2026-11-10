import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

struct WorkspacePairedDeviceCard: View {
    let device: WorkspacePairedDevice
    @Environment(WorkspaceStore.self) private var store
    @State private var showingDetails = false
    @State private var confirmingRevoke = false
    @State private var working = false
    @State private var failure: String?
    @State private var copiedID = false

    private var ru: Bool { store.language == "ru" }
    private var symbol: String { device.kind == .desktop ? "desktopcomputer" : "iphone" }
    private var kind: String {
        device.kind == .desktop ? (ru ? "Компьютер" : "Computer") : (ru ? "Телефон" : "Phone")
    }
    private var status: String {
        device.revoked ? (ru ? "Доступ отозван" : "Revoked") : store.t("Connected")
    }
    private var unavailable: Bool { working || store.busy }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    identity
                    Spacer(minLength: 8)
                    controls
                }
                VStack(alignment: .leading, spacing: 12) {
                    identity
                    HStack { Spacer(minLength: 0); controls }
                }
            }
            if let failure {
                Text(failure).font(.caption).foregroundStyle(.red)
                    .accessibilityIdentifier("paired-device.error")
            }
        }
        .padding(16)
        .background(WorkspaceStyle.secondary.opacity(0.05), in: .rect(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(WorkspaceStyle.secondary.opacity(0.12)) }
        .accessibilityIdentifier("paired-device.\(device.id)")
        .sheet(isPresented: $showingDetails) { details }
        .confirmationDialog(ru ? "Отозвать доступ у «\(device.name)»?" : "Revoke access for “\(device.name)”?",
                            isPresented: $confirmingRevoke, titleVisibility: .visible) {
            Button(ru ? "Отозвать доступ" : "Revoke access", role: .destructive) {
                _Concurrency.Task { await revoke() }
            }
            Button(store.t("Cancel"), role: .cancel) {}
        } message: {
            Text(ru ? "Устройство потеряет доступ к рабочему пространству. Для повторного подключения понадобится QR-код."
                 : "This device will lose access to your workspace. Connect it again using a QR code to restore access.")
        }
    }

    private var identity: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 24, weight: .medium))
                .frame(width: 48, height: 48)
                .background(WorkspaceStyle.secondary.opacity(0.08), in: .rect(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: device.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                Text(kind).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            Text(status).font(.caption2.weight(.medium))
                .foregroundStyle(device.revoked ? WorkspaceStyle.secondary : Color.green)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(device.revoked ? WorkspaceStyle.secondary.opacity(0.08) : Color.green.opacity(0.12), in: Capsule())
                .fixedSize()
            Menu {
                Button { showingDetails = true } label: {
                    Label(ru ? "Об устройстве" : "Device details", systemImage: "info.circle")
                }
                Button {
                    WorkspaceClipboard.copy(device.id.uuidString)
                    copiedID = true
                } label: {
                    Label(ru ? (copiedID ? "ID скопирован" : "Скопировать ID") : (copiedID ? "ID copied" : "Copy device ID"), systemImage: "doc.on.doc")
                }
                Button { _Concurrency.Task { await refresh() } } label: {
                    Label(ru ? "Обновить статус" : "Refresh status", systemImage: "arrow.clockwise")
                }.disabled(store.pairingCommands == nil)
                if !device.revoked && device.id != store.snapshot.localDeviceID {
                    Divider()
                    Button(role: .destructive) { confirmingRevoke = true } label: {
                        Label(ru ? "Отозвать доступ" : "Revoke access", systemImage: "xmark.shield")
                    }.disabled(store.pairingCommands == nil)
                }
            } label: {
                Group {
                    if working { ProgressView().controlSize(.small) }
                    else { Image(systemName: "ellipsis").font(.body.weight(.semibold)) }
                }
                .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).buttonStyle(.plain)
            .disabled(unavailable)
            .accessibilityLabel(ru ? "Действия с устройством \(device.name)" : "Actions for \(device.name)")
            .accessibilityIdentifier("paired-device.actions")
        }
    }

    private var details: some View {
        NavigationStack {
            Form {
                LabeledContent(ru ? "Имя" : "Name") { Text(verbatim: device.name) }
                LabeledContent(ru ? "Тип" : "Type", value: kind)
                LabeledContent(ru ? "Статус" : "Status", value: status)
                LabeledContent(ru ? "ID устройства" : "Device ID") {
                    Text(device.id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
            .navigationTitle(ru ? "Об устройстве" : "Device details")
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(ru ? "Готово" : "Done") { showingDetails = false }
            } }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 440, minHeight: 280).padding()
        #endif
    }

    private func refresh() async {
        guard !unavailable else { return }
        working = true; failure = nil
        defer { working = false }
        do { try await store.refreshDevices() }
        catch { failure = ru ? "Не удалось обновить статус. Попробуйте ещё раз." : "Could not refresh status. Try again." }
    }

    private func revoke() async {
        guard !unavailable, !device.revoked, let commands = store.pairingCommands else { return }
        working = true; failure = nil
        defer { working = false }
        do {
            try await commands.revokePairedDevice(device.id)
        } catch {
            failure = ru ? "Не удалось отозвать доступ. Попробуйте ещё раз." : "Could not revoke access. Try again."
            return
        }
        do { try await store.refreshDevices() }
        catch {
            failure = ru ? "Доступ отозван, но статус не обновился. Обновите его через меню."
                : "Access was revoked, but the status could not refresh. Refresh it from the menu."
        }
    }
}
