import BlotDesign
import SwiftUI
@preconcurrency import AVFoundation

struct PhoneQRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    func makeUIViewController(context: Context) -> CameraController { CameraController(onCode: onCode) }
    func updateUIViewController(_ controller: CameraController, context: Context) { }

    @MainActor
    final class CameraController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
        private let capture = AVCaptureSession()
        private let onCode: (String) -> Void
        private var preview: AVCaptureVideoPreviewLayer?
        private var delivered = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { return nil }
        override func viewDidLoad() {
            super.viewDidLoad(); view.backgroundColor = .black
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if allowed { self.configure() } else { self.showError("Camera access is unavailable. Paste the connection code instead.") }
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
            capture.startRunning()
        }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
        override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); capture.stopRunning() }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !delivered, let object = objects.first as? AVMetadataMachineReadableCodeObject, let code = object.stringValue else { return }
            delivered = true; capture.stopRunning(); onCode(code)
        }
        private func showError(_ text: String) { let label = UILabel(frame: view.bounds); label.text = text; label.textColor = .white; label.numberOfLines = 0; label.textAlignment = .center; label.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.addSubview(label) }
    }
}
