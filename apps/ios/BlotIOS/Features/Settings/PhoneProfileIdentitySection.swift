import BlotDesign
import PhotosUI
import SwiftUI

struct PhoneProfileIdentitySection: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var nickname = ""
    @State private var avatar: Data?
    @State private var photo: PhotosPickerItem?
    @State private var loadingPhoto = false
    @State private var avatarChanged = false
    @State private var saving = false
    @State private var initialized = false
    @State private var photoError: String?

    private var savedName: String { store.profile.nickname.isEmpty ? store.accountDisplayName : store.profile.nickname }
    private var hasChanges: Bool {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines) != savedName || avatarChanged
    }
    var body: some View {
        VStack(spacing: 20) {
            PhotosPicker(selection: $photo, matching: .images) {
                PhoneProfileAvatar(data: avatar, size: 104)
                    .overlay(alignment: .bottomTrailing) {
                        BlotIcon(.compose, size: 15).frame(width: 30, height: 30)
                            .background(PhoneSettingsStyle.row, in: Circle())
                            .overlay(Circle().strokeBorder(PhoneSettingsStyle.edge))
                    }
            }.buttonStyle(.plain).accessibilityLabel(store.t("Change avatar"))
            if avatar != nil {
                Button(store.t("Remove photo"), role: .destructive) { avatar = nil; photo = nil; avatarChanged = true }
                    .font(.footnote).buttonStyle(.plain)
            }
            VStack(spacing: 7) {
                Text(store.accountDisplayName).font(.title2.weight(.medium))
                Text(store.profile.contactEmail ?? store.form.account.email).font(.subheadline).foregroundStyle(.secondary)
            }
            PhoneSettingsGroup(title: "Personal details") {
                VStack(alignment: .leading, spacing: 16) {
                    Text(store.settingsText("Name")).font(.footnote).foregroundStyle(.secondary)
                    TextField(store.settingsText("Name"), text: $nickname)
                        .textContentType(.nickname).textFieldStyle(.plain).autocorrectionDisabled()
                        .accessibilityIdentifier("workspace.profile.name")
                    if loadingPhoto { ProgressView() }
                    if let photoError { Text(photoError).font(.footnote).foregroundStyle(.secondary) }
                    if hasChanges {
                        Button(store.t("Save")) { save() }.buttonStyle(.borderedProminent)
                            .disabled(loadingPhoto).accessibilityIdentifier("workspace.profile.save")
                    }
                    if saving { ProgressView() }
                }.padding(16)
            }
        }.frame(maxWidth: .infinity).disabled(saving)
            .onAppear {
                guard !initialized else { return }
                initialized = true; nickname = savedName; avatar = store.profile.avatar
            }
            .onChange(of: store.profile.avatar) { _, data in
                if !avatarChanged && !loadingPhoto { avatar = data }
            }
            .task(id: photo) {
                guard let photo else { loadingPhoto = false; return }
                loadingPhoto = true; photoError = nil
                defer { if self.photo == photo { loadingPhoto = false } }
                do {
                    guard let data = try await photo.loadTransferable(type: Data.self) else { throw PhoneAvatarImage.Failure.invalidImage }
                    let processed = try await Task.detached(priority: .userInitiated) { try PhoneAvatarImage.prepare(data) }.value
                    try Task.checkCancellation()
                    avatar = processed; avatarChanged = true
                } catch is CancellationError { }
                catch { photoError = store.t("The selected photo could not be loaded.") }
            }
    }
    private func save() {
        saving = true
        var value = store.profile
        value.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if avatarChanged { value.setCustomAvatar(avatar) }
        Task {
            defer { saving = false }
            if await store.saveProfile(value) { avatarChanged = false }
        }
    }
}
