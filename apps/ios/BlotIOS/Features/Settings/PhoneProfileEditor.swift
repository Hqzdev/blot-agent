import BlotDesign
import Foundation
import PhotosUI
import SwiftUI

struct PhoneProfileEditor: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var avatar: Data?
    @State private var photo: PhotosPickerItem?
    @State private var loadingPhoto = false
    @State private var photoError: String?
    @State private var initialized = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                PhotosPicker(selection: $photo, matching: .images) {
                    PhoneProfileAvatar(data: avatar, size: 100)
                        .overlay(alignment: .bottomTrailing) {
                            BlotIcon(.compose, size: 16).frame(width: 30, height: 30)
                                .background(WorkspaceStyle.canvas, in: Circle())
                                .overlay(Circle().strokeBorder(WorkspaceStyle.secondary.opacity(0.15)))
                        }
                }.buttonStyle(.plain).accessibilityLabel(store.t("Change avatar"))
                if avatar != nil {
                    Button(store.t("Remove photo"), role: .destructive) { avatar = nil; photo = nil }
                        .font(.subheadline).buttonStyle(.plain)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.t("Nickname")).font(.subheadline).foregroundStyle(WorkspaceStyle.secondary)
                    TextField(store.t("Nickname"), text: $nickname)
                        .textFieldStyle(.plain).textContentType(.nickname).autocorrectionDisabled()
                        .padding(16).background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                }
                if loadingPhoto { ProgressView() }
                if let photoError { Text(photoError).font(.footnote).foregroundStyle(WorkspaceStyle.secondary) }
                WorkspaceFeedback()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24).padding(.top, 28)
            .background(WorkspaceStyle.canvas)
            .navigationTitle(store.t("Edit profile")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.t("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("Save")) {
                        store.error = nil
                        store.profile = .init(nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines), avatar: avatar)
                        store.persistWorkspace(immediately: true)
                        if store.error == nil { dismiss() }
                    }.disabled(loadingPhoto || nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            nickname = store.profile.nickname.isEmpty
                ? [store.form.account.name, store.form.account.lastName].filter { !$0.isEmpty }.joined(separator: " ")
                : store.profile.nickname
            avatar = store.profile.avatar
            store.error = nil
        }
        .task(id: photo) {
            guard let photo else { loadingPhoto = false; return }
            loadingPhoto = true; photoError = nil
            defer { if self.photo == photo { loadingPhoto = false } }
            do {
                guard let data = try await photo.loadTransferable(type: Data.self) else { throw PhoneAvatarImage.Failure.invalidImage }
                let processed = try await _Concurrency.Task.detached(priority: .userInitiated) { try PhoneAvatarImage.prepare(data) }.value
                try _Concurrency.Task.checkCancellation()
                avatar = processed
            } catch is CancellationError { return }
            catch { photoError = store.t("The selected photo could not be loaded.") }
        }
    }
}
