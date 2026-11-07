import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

struct WorkspaceDevicePairingView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var pairing = WorkspaceDevicePairingSession()
    #if os(iOS)
    @State private var scanner = false
    @FocusState private var codeFocused: Bool
    #endif
    private var ru: Bool { store.language == "ru" }

    var body: some View {
        VStack(spacing: 22) {
            if pairing.phase == .complete {
                BlotIcon(.shieldCheck, size: 48).foregroundStyle(.green).accessibilityHidden(true)
                Text(ru ? "Устройства подключены" : "Devices connected").font(.title2.bold())
                Text(pairing.peerName).foregroundStyle(.secondary)
                #if os(macOS)
                Button(ru ? "Подключить ещё устройство" : "Connect another device") {
                    _Concurrency.Task { await beginHosting() }
                }.buttonStyle(WorkspaceButtonStyle(.secondary))
                #endif
            } else {
                #if os(macOS)
                desktop
                #else
                phone
                #endif
            }
            if let failure = pairing.failure {
                Text(failureText(failure)).font(.callout).foregroundStyle(.red)
                    .accessibilityIdentifier("pairing.error")
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 480).frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityIdentifier("pairing.setup")
        .task {
            #if os(macOS)
            await beginHosting()
            #endif
        }
        .onDisappear { pairing.stop() }
        .onChange(of: pairing.phase) { _, phase in
            if phase == .complete { _Concurrency.Task { try? await store.refreshDevices() } }
            #if os(iOS)
            codeFocused = phase == .enteringCode
            #endif
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $scanner) {
            NavigationStack {
                PhoneQRScanner(onCode: scan,
                    cameraAccessMessage: ru ? "Разрешите доступ к камере в настройках iPhone, чтобы отсканировать QR-код." : "Allow camera access in iPhone Settings to scan the QR code.")
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle(ru ? "QR-код на компьютере" : "Scan your computer’s QR code")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button(store.t("Cancel")) { scanner = false }
                    } }
            }
        }
        #endif
    }

    #if os(macOS)
    @ViewBuilder private var desktop: some View {
        Text(ru ? "Подключить iPhone" : "Connect iPhone").font(.title2.bold())
        Text(ru ? "Отсканируйте QR-код в Blot на iPhone, затем введите на телефоне код с этого экрана." : "Scan this QR code in Blot on iPhone, then enter the code shown here on your phone.")
            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        if !pairing.qrCode.isEmpty, pairing.phase != .failed {
            WorkspacePairingQRCode(value: pairing.qrCode)
            if !pairing.displayCode.isEmpty {
                Text(pairing.displayCode).font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                    .tracking(6).accessibilityLabel(pairing.displayCode.map(String.init).joined(separator: " "))
                    .accessibilityIdentifier("pairing.desktop-code")
            } else {
                Text(ru ? "Код появится после сканирования" : "Your code appears after scanning")
                    .font(.callout).foregroundStyle(.secondary)
            }
        } else if pairing.phase == .preparing { ProgressView() }
        if pairing.phase == .failed || store.pairingCommands == nil {
            Button(ru ? "Создать новый QR-код" : "Create a new QR code") {
                _Concurrency.Task { await beginHosting() }
            }.buttonStyle(WorkspaceButtonStyle()).disabled(store.pairingCommands == nil)
        }
        if pairing.phase == .waitingForReceipt || pairing.phase == .approving {
            ProgressView(ru ? "Подключаем…" : "Connecting…")
        }
    }

    private func beginHosting() async {
        guard let commands = store.pairingCommands else { return }
        await pairing.host(using: commands)
    }
    #else
    @ViewBuilder private var phone: some View {
        if pairing.phase == .enteringCode || pairing.phase == .confirming || pairing.phase == .finishing {
            BlotIcon(.computer, size: 48).accessibilityHidden(true)
            Text(ru ? "Введите код с компьютера" : "Enter the code from your computer").font(.title2.bold())
            Text(pairing.peerName).foregroundStyle(.secondary)
            TextField("000000", text: $pairing.code)
                .font(.system(.largeTitle, design: .monospaced)).multilineTextAlignment(.center)
                .keyboardType(.numberPad).textContentType(.oneTimeCode).focused($codeFocused)
                .padding(16).frame(maxWidth: 260)
                .background(WorkspaceStyle.secondary.opacity(0.08), in: .rect(cornerRadius: 16))
                .accessibilityLabel(ru ? "Шестизначный код" : "Six-digit code")
                .accessibilityIdentifier("pairing.phone-code")
                .onChange(of: pairing.code) { _, value in
                    pairing.code = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
                }
            Button(ru ? "Подключить" : "Connect") { pairing.confirm(); codeFocused = pairing.phase == .enteringCode }
                .buttonStyle(WorkspaceButtonStyle())
                .disabled(pairing.code.count != 6 || pairing.phase != .enteringCode)
            if pairing.phase != .enteringCode { ProgressView() }
        } else if pairing.phase == .connecting {
            ProgressView()
            Text(ru ? "Подключаемся к компьютеру…" : "Connecting to your computer…").font(.headline)
        } else {
            BlotIcon(.qr, size: 64).accessibilityHidden(true)
            Text(ru ? "Подключить компьютер" : "Connect computer").font(.title2.bold())
            Text(ru ? "Откройте «Устройства» в Blot на компьютере и отсканируйте QR-код." : "Open Devices in Blot on your computer and scan its QR code.")
                .foregroundStyle(.secondary)
            Button(ru ? "Сканировать QR-код" : "Scan QR code") { scanner = true }
                .buttonStyle(WorkspaceButtonStyle()).disabled(store.pairingCommands == nil)
                .accessibilityIdentifier("pairing.scan")
        }
    }

    private func scan(_ value: String) {
        scanner = false
        guard let commands = store.pairingCommands else { return }
        _Concurrency.Task { await pairing.join(value, using: commands) }
    }
    #endif

    private func failureText(_ failure: WorkspacePairingFailure) -> String {
        switch failure {
        case .wrongCode: ru ? "Код не совпадает. Введите шесть цифр с экрана компьютера." : "The code doesn’t match. Enter the six digits shown on your computer."
        case .expired: ru ? "Срок QR-кода истёк. Создайте новый на компьютере." : "This QR code expired. Create a new one on your computer."
        case .invalidQR: ru ? "Этот QR-код не подходит. Отсканируйте код из Blot на компьютере с тем же аккаунтом." : "Scan a Blot QR code from a computer signed into the same account."
        case .tooManyAttempts: ru ? "Слишком много попыток. Создайте новый QR-код." : "Too many attempts. Create a new QR code."
        default: ru ? "Не удалось подключиться. Проверьте доступ к локальной сети на обоих устройствах и создайте новый QR-код." : "Couldn’t connect. Check Local Network access on both devices and create a new QR code."
        }
    }
}

struct WorkspacePairedDevicesView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var failure: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(store.snapshot.pairedDevices ?? []) { device in
                HStack {
                    Label(device.name, systemImage: device.kind == .desktop ? "desktopcomputer" : "iphone")
                    Spacer()
                    Text(store.language == "ru" ? (device.revoked ? "Доступ отозван" : "Доверенное устройство") : (device.revoked ? "Revoked" : "Trusted"))
                    if !device.revoked {
                        Button(store.t("Revoke"), role: .destructive) {
                            _Concurrency.Task {
                                do { try await store.pairingCommands?.revokePairedDevice(device.id); try await store.refreshDevices() }
                                catch { failure = store.language == "ru" ? "Не удалось отозвать доступ." : "Could not revoke access." }
                            }
                        }
                    }
                }
            }
            if let failure { Text(failure).foregroundStyle(.red) }
            WorkspaceDevicePairingView()
        }
    }
}
