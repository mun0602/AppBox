//
//  MCQRScannerView.swift
//  LiveContainer
//
//  mun container — QR scanner (AVFoundation, works on all devices incl. A11)
//  Scan a QR code containing an install URL (http/https/file) for an
//  .ipa/.tipa and hand it to the existing install pipeline.
//

import SwiftUI
import AVFoundation

final class MCQRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onQR: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var started = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video) else {
            onError?("no camera")
            return
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            onError?("camera input failed")
            return
        }
        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            onError?("cannot add camera input")
            return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            onError?("cannot add camera output")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted {
                    self.started = true
                    self.session.startRunning()
                } else {
                    self.onError?("camera denied")
                }
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.stopRunning()
        started = false
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              obj.type == .qr,
              let value = obj.stringValue else { return }
        session.stopRunning()
        onQR?(value)
    }
}

struct MCQRScannerView: UIViewControllerRepresentable {
    var onQR: (String) -> Void
    var onError: (String) -> Void

    func makeUIViewController(context: Context) -> MCQRScannerController {
        let vc = MCQRScannerController()
        vc.onQR = onQR
        vc.onError = onError
        return vc
    }

    func updateUIViewController(_ vc: MCQRScannerController, context: Context) {}
}
