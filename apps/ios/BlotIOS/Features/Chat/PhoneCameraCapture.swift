import Foundation
import SwiftUI
import UIKit

struct PhoneCameraCapture: UIViewControllerRepresentable {
    let onPhoto: (Result<Data, Error>) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onPhoto: onPhoto, onDismiss: { dismiss() })
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onPhoto: (Result<Data, Error>) -> Void
        private let onDismiss: () -> Void

        init(onPhoto: @escaping (Result<Data, Error>) -> Void, onDismiss: @escaping () -> Void) {
            self.onPhoto = onPhoto
            self.onDismiss = onDismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.92) {
                onPhoto(.success(data))
            } else { onPhoto(.failure(PhoneAttachmentError.photoUnavailable)) }
            onDismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onDismiss() }
    }
}
