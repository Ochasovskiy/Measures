//
//  PhotoCaptureView.swift
//  MeasureGo
//
//  In-app camera for pool photos, replacing the system picker.
//
//  Unity drew a per-photo tip and a "2 / 4" counter over the live feed and kept
//  the camera open for the whole set (TakePhotoPanelView). The system picker can
//  do neither, so reps lost track of which side of the pool they were shooting
//  and bounced back to the form after every photo — the first thing the client
//  flagged when comparing the two apps.
//
//  Photos stay at full resolution (~12 MP), unlike Unity, which saved a
//  screenshot of the AR view at screen resolution.
//

import AVFoundation
import Combine
import SwiftUI
import UIKit

struct PhotoCaptureView: View {

    /// One tip per side, indexed by how many photos already exist. Unity's
    /// first tip was the general "minimum of four" line rather than Side A;
    /// every shot now names its side, and that line moves underneath.
    static let tips = [
        "Take a picture of Side A of the pool",
        "Take a picture of Side B of the pool",
        "Take a picture of Side C of the pool",
        "Take a picture of Side D of the pool",
    ]
    static let setHint = "Take a minimum of four pictures to best display the pool project"
    static let recommendedCount = 4

    static func tip(forPhotosTaken count: Int) -> String {
        tips.indices.contains(count) ? tips[count] : "Add any other photos that help show the pool"
    }

    /// The project's **live** photo count — the only counter there is.
    ///
    /// An earlier version kept its own "taken" tally on top of a starting
    /// count, and double-counted: adding a photo re-renders the presenting
    /// screen, which hands this view a new count that already includes it,
    /// while the private tally went up as well. The second photo was labelled
    /// Side C and the camera closed after three. Reading one source of truth
    /// makes that impossible.
    let photoCount: Int
    /// Close once this many photos exist, as Unity did at four. Nil = no cap.
    let limit: Int?
    let onPhoto: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraModel()

    private var count: Int { photoCount }

    private var counterText: String {
        count < Self.recommendedCount
            ? "\(count) / \(Self.recommendedCount)"
            : "\(count) photos"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.status {
            case .starting, .ready:
                if let photo = camera.captured {
                    review(photo)
                } else {
                    viewfinder
                }
            case .denied:
                message(
                    "Camera access is off",
                    "Allow MeasureGo to use the camera in Settings to take pool photos.",
                    showSettings: true
                )
            case .unavailable:
                message(
                    "Camera unavailable",
                    "This device's camera couldn't be started.",
                    showSettings: false
                )
            }
        }
        .statusBarHidden()
        // Close only once the limit is genuinely reached — reacting to the
        // project's own count means a photo that failed to save never counts.
        .onChange(of: photoCount) { _, newCount in
            if let limit, newCount >= limit { dismiss() }
        }
        .task { await camera.start() }
        .onAppear { OrientationLock.mask = .portrait }
        .onDisappear {
            camera.stop()
            OrientationLock.mask = .all
        }
    }

    // MARK: - Viewfinder

    private var viewfinder: some View {
        ZStack {
            // Aspect-fit, not fill: the photo is the full 4:3 frame, so the
            // preview must show exactly that or reps frame a side and get more
            // (or less) than they saw.
            CameraPreview(session: camera.session) { layer in
                camera.attach(previewLayer: layer)
            }
            .ignoresSafeArea()

            VStack(spacing: 10) {
                HStack {
                    Button("Done") { dismiss() }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(MainView.navy.opacity(0.85))
                        .clipShape(Capsule())

                    Spacer()

                    Text(counterText)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(MainView.navy.opacity(0.85))
                        .clipShape(Capsule())
                }

                // The instruction lives on the feed itself, where the rep is
                // actually looking while framing the shot.
                VStack(spacing: 4) {
                    Text(Self.tip(forPhotosTaken: count))
                        .font(.subheadline.weight(.semibold))
                    if count < Self.recommendedCount {
                        Text(Self.setHint)
                            .font(.caption)
                            .opacity(0.8)
                    }
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(MainView.navy.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                Spacer()

                shutterButton
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var shutterButton: some View {
        Button {
            Task { await camera.capture() }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(.white)
                    .frame(width: 62, height: 62)
                if camera.isCapturing {
                    ProgressView().tint(MainView.navy)
                }
            }
        }
        .disabled(camera.status != .ready || camera.isCapturing)
        .opacity(camera.status == .ready ? 1 : 0.4)
        .accessibilityLabel("Take photo")
    }

    // MARK: - Review (Unity's Remake / Use photo)

    private func review(_ photo: UIImage) -> some View {
        VStack(spacing: 16) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 14) {
                Button {
                    camera.discardCaptured()
                } label: {
                    Text("Retake")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(MainView.navy.opacity(0.85))
                        .clipShape(Capsule())
                }

                Button {
                    usePhoto(photo)
                } label: {
                    Text("Use photo")
                        .font(.headline)
                        .foregroundStyle(MainView.navy)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(.white)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    private func usePhoto(_ photo: UIImage) {
        onPhoto(photo)
        camera.discardCaptured()
        // No counting or closing here: the project's count updates, this view
        // receives it, and `onChange(of: photoCount)` decides whether to close.
    }

    // MARK: - Permission / failure

    private func message(_ title: String, _ detail: String, showSettings: Bool) -> some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            if showSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { UIApplication.shared.open(url) }
                    .buttonStyle(.borderedProminent)
                    .tint(MainView.salmon)
            }
            Button("Close") { dismiss() }
                .foregroundStyle(.white)
        }
        .padding(32)
    }
}

// MARK: - Camera model

/// Main-actor face of the camera: publishes state for the UI and owns the
/// rotation coordinator, which has to be tied to the on-screen preview layer.
final class CameraModel: ObservableObject {

    enum Status: Equatable { case starting, ready, denied, unavailable }

    @Published private(set) var status: Status = .starting
    @Published private(set) var captured: UIImage?
    @Published private(set) var isCapturing = false

    private let capture = CaptureSession()
    var session: AVCaptureSession { capture.session }

    private var device: AVCaptureDevice?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var previewAngleObservation: NSKeyValueObservation?

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                status = .denied
                return
            }
        default:
            status = .denied
            return
        }

        guard let device = await capture.configureAndStart() else {
            status = .unavailable
            return
        }
        self.device = device
        makeRotationCoordinatorIfReady()
        status = .ready
    }

    func stop() {
        previewAngleObservation = nil
        capture.stop()
    }

    /// The preview layer and the device arrive in either order — the layer
    /// when SwiftUI builds the view, the device once configuration finishes —
    /// so the coordinator is built by whichever lands second.
    func attach(previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
        makeRotationCoordinatorIfReady()
    }

    private func makeRotationCoordinatorIfReady() {
        guard rotation == nil, let device, let previewLayer else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotation = coordinator
        previewAngleObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]
        ) { [weak previewLayer] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            DispatchQueue.main.async {
                guard let connection = previewLayer?.connection,
                      connection.isVideoRotationAngleSupported(angle) else { return }
                connection.videoRotationAngle = angle
            }
        }
    }

    func capture() async {
        guard status == .ready, !isCapturing, captured == nil else { return }
        isCapturing = true
        // Taken from how the phone is physically held, not from the interface
        // (which is pinned to portrait) — a landscape shot of a long side
        // comes out landscape.
        let angle = rotation?.videoRotationAngleForHorizonLevelCapture ?? 90
        let image = await capture.capturePhoto(rotationAngle: angle)
        isCapturing = false
        captured = image
    }

    func discardCaptured() {
        captured = nil
    }
}

/// Owns the AVCaptureSession and does all of its work on one private serial
/// queue: `startRunning()` blocks for hundreds of milliseconds and must never
/// run on the main thread. Every mutable property is touched only from
/// `queue`, which is what makes the unchecked Sendable sound.
nonisolated final class CaptureSession: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.latham.MeasureGo.camera")
    private var configured = false
    private var device: AVCaptureDevice?
    private var pending: ((UIImage?) -> Void)?

    /// Keeps parity with the photos the system picker produced (4032x3024).
    /// Pro phones can capture 48 MP, which would quadruple every upload for no
    /// benefit to a photo documenting the side of a pool.
    private static let maxPixels = 12_600_000

    func configureAndStart() async -> AVCaptureDevice? {
        await withCheckedContinuation { continuation in
            queue.async {
                if !self.configured {
                    self.device = self.configure()
                    self.configured = true
                }
                if self.device != nil, !self.session.isRunning {
                    self.session.startRunning()
                }
                continuation.resume(returning: self.device)
            }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func configure() -> AVCaptureDevice? {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(output)
        else { return nil }

        session.addInput(input)
        session.addOutput(output)

        let pixels = { (d: CMVideoDimensions) in Int(d.width) * Int(d.height) }
        if let dimensions = device.activeFormat.supportedMaxPhotoDimensions
            .filter({ pixels($0) <= Self.maxPixels })
            .max(by: { pixels($0) < pixels($1) }) {
            output.maxPhotoDimensions = dimensions
        }
        output.maxPhotoQualityPrioritization = .balanced
        return device
    }

    func capturePhoto(rotationAngle: CGFloat) async -> UIImage? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard self.pending == nil, self.session.isRunning else {
                    continuation.resume(returning: nil)
                    return
                }
                if let connection = self.output.connection(with: .video),
                   connection.isVideoRotationAngleSupported(rotationAngle) {
                    connection.videoRotationAngle = rotationAngle
                }
                let settings = AVCapturePhotoSettings()
                settings.maxPhotoDimensions = self.output.maxPhotoDimensions
                // Same trade-off the system camera makes by default: good
                // detail without the multi-second fusion wait of `.quality`.
                settings.photoQualityPrioritization = .balanced
                self.pending = { continuation.resume(returning: $0) }
                self.output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        // The rotation set on the connection arrives as orientation metadata;
        // ProjectStore.savePhoto bakes it into the pixels when saving.
        let image = error == nil ? photo.fileDataRepresentation().flatMap(UIImage.init(data:)) : nil
        queue.async {
            let finish = self.pending
            self.pending = nil
            finish?(image)
        }
    }
}

// MARK: - Preview

private struct CameraPreview: UIViewRepresentable {

    let session: AVCaptureSession
    let onLayer: (AVCaptureVideoPreviewLayer) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        onLayer(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            // Guaranteed by layerClass above.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
