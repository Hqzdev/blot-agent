import BlotDesign
import SwiftUI
@preconcurrency import AVFoundation

struct PhoneQRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    var cameraAccessMessage = "Camera access is unavailable. Paste the connection code instead."
    func makeUIViewController(context: Context) -> CameraController {
        CameraController(onCode: onCode, cameraAccessMessage: cameraAccessMessage)
    }
    func updateUIViewController(_ controller: CameraController, context: Context) { }

    @MainActor
    final class CameraController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
        private let capture = AVCaptureSession()
        private let onCode: (String) -> Void
        private let cameraAccessMessage: String
        private let captureQueue = DispatchQueue(label: "dev.blot.qr-camera")
        private var preview: AVCaptureVideoPreviewLayer?
        private var delivered = false
        private var closed = false
        init(onCode: @escaping (String) -> Void, cameraAccessMessage: String) {
            self.onCode = onCode; self.cameraAccessMessage = cameraAccessMessage
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { return nil }
        override func viewDidLoad() {
            super.viewDidLoad(); view.backgroundColor = .black
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                Task { @MainActor [weak self] in
                    guard let self, !self.closed else { return }
                    if allowed { self.configure() } else { self.showError(self.cameraAccessMessage) }
                }
            }
        }
        private func configure() {
            guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), capture.canAddInput(input) else { showError("No camera is available."); return }
            capture.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard capture.canAddOutput(output) else { showError("QR scanning is unavailable."); return }
            capture.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]
            let preview = AVCaptureVideoPreviewLayer(session: capture); preview.videoGravity = .resizeAspectFill; view.layer.addSublayer(preview); self.preview = preview
            let capture = capture
            captureQueue.async { capture.startRunning() }
        }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
        override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); closed = true; stopCapture() }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !closed, !delivered, let object = objects.first as? AVMetadataMachineReadableCodeObject, let code = object.stringValue else { return }
            delivered = true; stopCapture(); onCode(code)
        }
        private func stopCapture() {
            let capture = capture
            captureQueue.async { capture.stopRunning() }
        }
        private func showError(_ text: String) { let label = UILabel(frame: view.bounds); label.text = text; label.textColor = .white; label.numberOfLines = 0; label.textAlignment = .center; label.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.addSubview(label) }
    }
}
