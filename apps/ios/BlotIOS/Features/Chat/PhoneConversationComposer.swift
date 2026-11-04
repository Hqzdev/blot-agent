import BlotDesign
import BlotDomain
import AVFoundation
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PhoneConversationComposer: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var menu = PhoneComposerMenuState()
    @State private var source: PhoneAttachmentSource?
    @State private var loadingAttachments = false
    @Environment(\.blotReduceMotion) private var reduceMotion
    @FocusState private var messageFocused: Bool
    private let storage = PhoneAttachmentStorage()

    private var canSend: Bool {
        !store.form.composer.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.form.composer.attachments.isEmpty
    }

    var body: some View {
        @Bindable var store = store
        GlassEffectContainer(spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                if let target = store.currentReplyTarget {
                    HStack(spacing: 8) {
                        BlotIcon(.reply, size: 18).foregroundStyle(WorkspaceStyle.secondary)
                        WorkspaceQuotedMessage(message: target)
                        Button { store.form.composer.replyToMessageID = nil } label: {
                            BlotIcon(.close, size: 14).frame(width: 32, height: 32)
                        }.buttonStyle(.plain).accessibilityLabel(store.t("Cancel reply"))
                    }.padding(10).background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                }
                if !store.form.composer.attachments.isEmpty {
                    PhoneComposerAttachments(urls: $store.form.composer.attachments)
                }
                PhoneComposerBar(menu: menu, loadingAttachments: loadingAttachments, canSend: canSend,
                                 focused: $messageFocused, send: send)
            }
        }
        .kAnimation(KMotion.panel, value: menu.isOpen)
        .onDisappear { messageFocused = false; menu.dismiss() }
        .task(id: store.selectedConversationID) {
            menu.dismiss()
            messageFocused = store.currentMessages.isEmpty
        }
        .onChange(of: store.replyFocusRequest) { _, _ in
            withKAnimation(reduceMotion, KMotion.panel) { menu.dismiss() }
            messageFocused = true
        }
        .onChange(of: store.agentPickerVisible) { _, visible in
            if !visible && store.currentMessages.isEmpty { messageFocused = true }
        }
        .onChange(of: menu.page) { _, page in
            if page == .photos { messageFocused = false }
        }
        .task(id: menu.request?.id) {
            guard let request = menu.request else { return }
            if request.source == .photos { await loadPhotos(request.photos) }
            else { await selectSource(request.source) }
        }
        .fullScreenCover(isPresented: presented(.camera)) {
            PhoneCameraCapture { result in
                switch result {
                case .success(let data): _Concurrency.Task { await savePhoto(data, fileExtension: "jpg") }
                case .failure(let error): store.error = store.t(error.localizedDescription)
                }
            }.ignoresSafeArea()
        }
        .fileImporter(isPresented: presented(.files), allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                _Concurrency.Task { await importFiles(urls) }
            case .failure(let error):
                let failure = error as NSError
                if failure.domain != NSCocoaErrorDomain || failure.code != NSUserCancelledError { store.error = error.localizedDescription }
            }
        }
        .sensoryFeedback(.selection, trigger: menu.page)
    }

    private func presented(_ destination: PhoneAttachmentSource) -> Binding<Bool> {
        Binding(get: { source == destination }, set: { visible in
            if visible { source = destination }
            else if source == destination { source = nil }
        })
    }

    private func selectSource(_ selected: PhoneAttachmentSource) async {
        messageFocused = false
        if selected == .plugins {
            store.pluginCatalogVisible = true
            return
        }
        let conversationID = store.selectedConversationID
        if selected == .camera {
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                store.error = store.t(PhoneAttachmentError.cameraUnavailable.rawValue)
                return
            }
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            guard !_Concurrency.Task.isCancelled else { return }
            guard allowed else { store.error = store.t(PhoneAttachmentError.cameraDenied.rawValue); return }
            guard store.selectedConversationID == conversationID else { return }
        }
        guard !_Concurrency.Task.isCancelled else { return }
        source = selected
    }

    private func loadPhotos(_ photos: [PhotosPickerItem]) async {
        guard !photos.isEmpty else { return }
        let conversationID = store.selectedConversationID
        loadingAttachments = true
        defer { loadingAttachments = false }
        do {
            for photo in photos {
                guard let data = try await photo.loadTransferable(type: Data.self) else { throw PhoneAttachmentError.photoUnavailable }
                try _Concurrency.Task.checkCancellation()
                let fileExtension = photo.supportedContentTypes.first(where: { $0.conforms(to: .image) })?.preferredFilenameExtension ?? "jpg"
                let url = try await storage.savePhoto(data, fileExtension: fileExtension)
                try _Concurrency.Task.checkCancellation()
                guard store.selectedConversationID == conversationID else { return }
                store.form.composer.attachments.append(url)
            }
        } catch is CancellationError { return }
        catch { store.error = store.t(error.localizedDescription) }
    }

    private func savePhoto(_ data: Data, fileExtension: String) async {
        let conversationID = store.selectedConversationID
        loadingAttachments = true
        defer { loadingAttachments = false }
        do {
            let url = try await storage.savePhoto(data, fileExtension: fileExtension)
            guard store.selectedConversationID == conversationID else { return }
            store.form.composer.attachments.append(url)
        } catch { store.error = store.t(error.localizedDescription) }
    }

    private func importFiles(_ urls: [URL]) async {
        let conversationID = store.selectedConversationID
        loadingAttachments = true
        defer { loadingAttachments = false }
        do {
            for original in urls {
                let imported = try await storage.importFile(original)
                guard store.selectedConversationID == conversationID else { return }
                store.form.composer.attachments.append(imported)
            }
        } catch { store.error = store.t(error.localizedDescription) }
    }

    private func send() {
        guard canSend, !store.busy, !loadingAttachments else { return }
        _Concurrency.Task { await store.perform(.send) }
    }
}
