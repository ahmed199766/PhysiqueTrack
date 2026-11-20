import SwiftUI
import AVFoundation
import UIKit

final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()

    @Published var isAuthorized = false
    @Published var permissionDenied = false
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var capturedImage: UIImage?
    @Published var isCapturing = false

    private let sessionQueue = DispatchQueue(label: "com.physiquetrack.camera.queue")
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var isConfigured = false

    func checkPermissionsAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { self.isAuthorized = true }
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.isAuthorized = granted
                    self.permissionDenied = !granted
                }
                if granted {
                    self.configureAndStart()
                }
            }
        default:
            DispatchQueue.main.async {
                self.isAuthorized = false
                self.permissionDenied = true
            }
        }
    }

    private func configureAndStart() {
        sessionQueue.async {
            if !self.isConfigured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                self.attachCamera(position: self.cameraPosition)
                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                }
                self.session.commitConfiguration()
                self.isConfigured = true
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    private func attachCamera(position: AVCaptureDevice.Position) {
        if let existing = currentInput {
            session.removeInput(existing)
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return
        }
        session.addInput(input)
        currentInput = input
    }

    func switchCamera() {
        let nextPosition: AVCaptureDevice.Position = (cameraPosition == .back) ? .front : .back
        DispatchQueue.main.async { self.cameraPosition = nextPosition }
        sessionQueue.async {
            self.session.beginConfiguration()
            self.attachCamera(position: nextPosition)
            self.session.commitConfiguration()
        }
    }

    func capturePhoto() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            DispatchQueue.main.async { self.isCapturing = true }
            let settings = AVCapturePhotoSettings()
            if let connection = self.photoOutput.connection(with: .video),
               connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        DispatchQueue.main.async { self.isCapturing = false }
        guard error == nil, let data = photo.fileDataRepresentation(),
              let rawImage = UIImage(data: data) else {
            return
        }
        let finalImage = rawImage.normalizedUp(maxDimension: 1600)
        DispatchQueue.main.async {
            self.capturedImage = finalImage
        }
    }
}

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

struct CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }
}

struct GhostCameraView: View {
    let angle: PhotoAngle
    let ghostImage: UIImage?
    let onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = CameraController()

    @State private var ghostOpacity: Double = 0.35
    @State private var showGrid: Bool = true
    @State private var selectedTimerSeconds: Int = 0
    @State private var countdownRemaining: Int = 0
    @State private var timerTask: Task<Void, Never>?

    private let timerOptions = [0, 3, 5, 10]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let preview = controller.capturedImage {
                capturedReviewView(preview)
            } else if controller.permissionDenied {
                permissionDeniedView
            } else {
                liveCameraView
            }
        }
        .onAppear {
            controller.checkPermissionsAndStart()
        }
        .onDisappear {
            timerTask?.cancel()
            controller.stop()
        }
    }

    private var liveCameraView: some View {
        ZStack {
            CameraPreviewRepresentable(session: controller.session)
                .ignoresSafeArea()

            if let ghost = ghostImage, ghostOpacity > 0.01 {
                Image(uiImage: ghost)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .opacity(ghostOpacity)
                    .allowsHitTesting(false)
            }

            if showGrid {
                CameraGridOverlay()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            if countdownRemaining > 0 {
                Text("\(countdownRemaining)")
                    .font(.system(size: 110, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.8), radius: 12)
                    .transition(.scale)
            }

            VStack {
                topBar
                Spacer()
                bottomControls
            }
            .padding()
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                timerTask?.cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            Text("زاوية: \(angle.arabicTitle)")
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            Button {
                showGrid.toggle()
            } label: {
                Image(systemName: showGrid ? "grid" : "grid.circle")
                    .font(.headline)
                    .foregroundColor(showGrid ? .accentColor : .white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.top, 8)
    }

    private var bottomControls: some View {
        VStack(spacing: 16) {
            if ghostImage != nil {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .foregroundColor(.white.opacity(0.85))
                    Slider(value: $ghostOpacity, in: 0...0.75)
                        .tint(.accentColor)
                    Text("\(Int(ghostOpacity * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white)
                        .frame(width: 38)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            } else {
                Text("أول صورة لهذه الزاوية — ستُستخدم كمرجع شفاف في المرة القادمة")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
            }

            // Timer selector
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .foregroundColor(.white)
                ForEach(timerOptions, id: \.self) { sec in
                    Button {
                        selectedTimerSeconds = sec
                    } label: {
                        Text(sec == 0 ? "فوري" : "\(sec)ث")
                            .font(.caption.bold())
                            .foregroundColor(selectedTimerSeconds == sec ? .black : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                selectedTimerSeconds == sec ? Color.accentColor : Color.white.opacity(0.18),
                                in: Capsule()
                            )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())

            HStack {
                Color.clear.frame(width: 48, height: 48)
                Spacer()

                Button {
                    triggerCapture()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 74, height: 74)
                        Circle()
                            .fill(countdownRemaining > 0 ? Color.red : Color.white)
                            .frame(width: 62, height: 62)
                    }
                }
                .disabled(controller.isCapturing)

                Spacer()

                Button {
                    controller.switchCamera()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func triggerCapture() {
        if countdownRemaining > 0 {
            timerTask?.cancel()
            countdownRemaining = 0
            return
        }

        if selectedTimerSeconds == 0 {
            let feedback = UIImpactFeedbackGenerator(style: .medium)
            feedback.impactOccurred()
            controller.capturePhoto()
            return
        }

        countdownRemaining = selectedTimerSeconds
        timerTask?.cancel()
        timerTask = Task {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            while countdownRemaining > 0 {
                if Task.isCancelled { return }
                haptic.impactOccurred()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                await MainActor.run {
                    countdownRemaining -= 1
                }
            }
            await MainActor.run {
                let snapHaptic = UIImpactFeedbackGenerator(style: .heavy)
                snapHaptic.impactOccurred()
                controller.capturePhoto()
            }
        }
    }

    private func capturedReviewView(_ image: UIImage) -> some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .ignoresSafeArea()

            VStack {
                Spacer()
                HStack(spacing: 20) {
                    Button {
                        controller.capturedImage = nil
                    } label: {
                        Label("إعادة الالتقاط", systemImage: "arrow.counterclockwise")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }

                    Button {
                        onCapture(image)
                        dismiss()
                    } label: {
                        Label("اعتماد الصورة", systemImage: "checkmark")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding()
                .background(.black.opacity(0.55))
            }
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            Text("لا يوجد إذن للوصول إلى الكاميرا")
                .font(.headline)
                .foregroundColor(.white)
            Text("يرجى تفعيل صلاحية الكاميرا من إعدادات الآيفون لاستخدام كاميرا التطابق.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            HStack(spacing: 12) {
                Button("إغلاق") { dismiss() }
                    .buttonStyle(.bordered)
                Button("فتح الإعدادات") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

struct CameraGridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width
                let h = geo.size.height
                path.move(to: CGPoint(x: w / 3, y: 0))
                path.addLine(to: CGPoint(x: w / 3, y: h))
                path.move(to: CGPoint(x: 2 * w / 3, y: 0))
                path.addLine(to: CGPoint(x: 2 * w / 3, y: h))
                path.move(to: CGPoint(x: 0, y: h / 3))
                path.addLine(to: CGPoint(x: w, y: h / 3))
                path.move(to: CGPoint(x: 0, y: 2 * h / 3))
                path.addLine(to: CGPoint(x: w, y: 2 * h / 3))
                // Center vertical alignment guide
                path.move(to: CGPoint(x: w / 2, y: 0))
                path.addLine(to: CGPoint(x: w / 2, y: h))
            }
            .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
        }
    }
}
