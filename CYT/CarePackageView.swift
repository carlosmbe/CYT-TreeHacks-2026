//
//  CarePackageView.swift
//  CYT
//
//  Main check-in flow: idle → recording → followUp → processing → result.
//

import SwiftUI
import AVFoundation

struct CarePackageView: View {
    enum Phase {
        case idle
        case recording
        case followUp
        case processing
        case result
    }

    @State private var phase: Phase = .idle
    @State private var selectedScenario: MockScenario = .stressedAndTired
    @State private var currentPackage: CarePackage?
    @State private var journalStore = JournalStore()

    // Follow-up state
    @State private var followUpText = ""
    @State private var preferToType = false
    @State private var followUpRecording = false
    @State private var followUpRecordingDone = false
    @State private var capturedPhoto: UIImage?

    // Processing animation
    @State private var processingStep = 0
    @State private var recordingPulse = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                switch phase {
                case .idle:
                    idleView
                case .recording:
                    recordingView
                case .followUp:
                    followUpView
                case .processing:
                    processingView
                case .result:
                    if let pkg = currentPackage {
                        resultView(pkg)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: CardCategory.self) { category in
                if category == .express, let pkg = currentPackage {
                    JournalEntryView(package: pkg)
                }
            }
            .toolbar {
                if phase == .result {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("New Check-In") {
                            resetFlow()
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    scenarioPicker
                }
            }
        }
        .environment(journalStore)
    }

    private var navigationTitle: String {
        switch phase {
        case .result: return "Your Care Package"
        case .followUp: return "One More Thing"
        default: return "Check In"
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 32) {
            Spacer()

            CameraPreviewView(capturedPhoto: .constant(nil), triggerCapture: .constant(false))
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 2))
                .shadow(color: .black.opacity(0.2), radius: 10)

            VStack(spacing: 8) {
                Text("How are you feeling?")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Tap the mic and speak for a moment")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    phase = .recording
                }
                startRecordingSequence()
            } label: {
                ZStack {
                    Circle()
                        .fill(.blue.gradient)
                        .frame(width: 80, height: 80)
                    Image(systemName: "mic.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                }
            }
            .accessibilityLabel("Start check-in")

            Spacer()
            Spacer()
        }
    }

    // MARK: - Recording

    @State private var triggerCapture = false

    private var recordingView: some View {
        VStack(spacing: 32) {
            Spacer()

            CameraPreviewView(capturedPhoto: $capturedPhoto, triggerCapture: $triggerCapture)
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(.red.opacity(recordingPulse ? 0.6 : 0.2), lineWidth: 3)
                        .scaleEffect(recordingPulse ? 1.15 : 1.0)
                )
                .shadow(color: .red.opacity(0.2), radius: 10)

            VStack(spacing: 8) {
                Text("Listening...")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Speak freely about how you're feeling")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ZStack {
                Circle()
                    .fill(.red.opacity(recordingPulse ? 0.15 : 0.05))
                    .frame(width: 100, height: 100)

                Circle()
                    .fill(.red.gradient)
                    .frame(width: 64, height: 64)

                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            }

            Spacer()
            Spacer()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                recordingPulse = true
            }
        }
        .onDisappear {
            recordingPulse = false
        }
    }

    // MARK: - Follow-Up

    @State private var followUpPulse = false

    private var followUpView: some View {
        VStack(spacing: 0) {
            Spacer()

            // Guiding question
            let question = MockSignalProvider.carePackage(for: selectedScenario).followUpQuestion
            VStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.title2)
                    .foregroundStyle(.blue)

                Text(question)
                    .font(.title3)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.bottom, 28)

            if preferToType {
                // Text input mode
                TextField("Type your thoughts...", text: $followUpText, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                Button {
                    withAnimation { phase = .processing }
                    startProcessingSequence()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.blue.gradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 20)
            } else if followUpRecordingDone {
                // Done recording follow-up
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(.green.opacity(0.15))
                            .frame(width: 80, height: 80)
                        Image(systemName: "checkmark")
                            .font(.title)
                            .foregroundStyle(.green)
                    }

                    Text("Got it")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 20)

                Button {
                    withAnimation { phase = .processing }
                    startProcessingSequence()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.blue.gradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 20)
            } else if followUpRecording {
                // Recording follow-up answer
                ZStack {
                    Circle()
                        .fill(.red.opacity(followUpPulse ? 0.15 : 0.05))
                        .frame(width: 100, height: 100)

                    Circle()
                        .fill(.red.gradient)
                        .frame(width: 64, height: 64)

                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        followUpPulse = true
                    }
                    // Auto-stop after 5 seconds
                    Task {
                        try? await Task.sleep(for: .seconds(5))
                        await MainActor.run {
                            followUpPulse = false
                            withAnimation { followUpRecordingDone = true; followUpRecording = false }
                        }
                    }
                }

                Text("Listening...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
                // Mic button to start follow-up recording
                Button {
                    withAnimation { followUpRecording = true }
                } label: {
                    ZStack {
                        Circle()
                            .fill(.blue.gradient)
                            .frame(width: 72, height: 72)
                        Image(systemName: "mic.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
                .accessibilityLabel("Record your answer")
            }

            Spacer()

            // Toggle at the bottom
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    preferToType.toggle()
                    followUpRecording = false
                    followUpRecordingDone = false
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: preferToType ? "mic.fill" : "keyboard")
                        .font(.caption)
                    Text(preferToType ? "Prefer to speak?" : "Prefer to type?")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Processing

    private var processingView: some View {
        VStack(spacing: 40) {
            Spacer()

            Text("Understanding your check-in...")
                .font(.title3)
                .fontWeight(.medium)

            VStack(alignment: .leading, spacing: 20) {
                signalRow(icon: "ear.fill", text: "Listening to your voice...", step: 0)
                signalRow(icon: "eye.fill", text: "Reading your expression...", step: 1)
                signalRow(icon: "heart.fill", text: "Checking your vitals...", step: 2)
            }

            Spacer()
            Spacer()
        }
    }

    private func signalRow(icon: String, text: String, step: Int) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(processingStep > step ? Color.green.opacity(0.15) : Color.secondary.opacity(0.08))
                    .frame(width: 40, height: 40)

                if processingStep == step {
                    ProgressView()
                        .tint(.blue)
                } else if processingStep > step {
                    Image(systemName: "checkmark")
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text(text)
                .font(.body)
                .foregroundStyle(processingStep >= step ? .primary : .tertiary)
        }
        .animation(.easeInOut(duration: 0.3), value: processingStep)
    }

    // MARK: - Result

    private func resultView(_ package: CarePackage) -> some View {
        CarePackageResultView(package: package)
    }

    // MARK: - Scenario Picker

    private var scenarioPicker: some View {
        Menu {
            ForEach(MockScenario.allCases) { scenario in
                Button {
                    selectedScenario = scenario
                } label: {
                    if scenario == selectedScenario {
                        Label(scenario.rawValue, systemImage: "checkmark")
                    } else {
                        Text(scenario.rawValue)
                    }
                }
            }
        } label: {
            Image(systemName: "flask.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Demo scenario")
    }

    // MARK: - Flow Logic

    private func startRecordingSequence() {
        Task {
            // Auto-snap a selfie ~2s into recording
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { triggerCapture = true }
            // Finish recording at 3s
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run {
                recordingPulse = false
                withAnimation { phase = .followUp }
            }
        }
    }

    private func startProcessingSequence() {
        Task {
            for i in 1...3 {
                try? await Task.sleep(for: .seconds(0.8))
                await MainActor.run {
                    withAnimation { processingStep = i }
                }
            }
            try? await Task.sleep(for: .seconds(0.5))
            let pkg = MockSignalProvider.carePackage(for: selectedScenario)
            await MainActor.run {
                currentPackage = pkg
                processingStep = 0
                withAnimation(.easeInOut(duration: 0.4)) {
                    phase = .result
                }
            }
        }
    }

    private func resetFlow() {
        withAnimation {
            phase = .idle
            currentPackage = nil
            followUpText = ""
            preferToType = false
            followUpRecording = false
            followUpRecordingDone = false
            capturedPhoto = nil
            triggerCapture = false
            processingStep = 0
        }
    }
}

// MARK: - Camera Preview with Snapshot Support

#if os(iOS)
struct CameraPreviewView: UIViewRepresentable {
    @Binding var capturedPhoto: UIImage?
    @Binding var triggerCapture: Bool

    init(capturedPhoto: Binding<UIImage?>, triggerCapture: Binding<Bool> = .constant(false)) {
        _capturedPhoto = capturedPhoto
        _triggerCapture = triggerCapture
    }

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.onCapture = { image in
            DispatchQueue.main.async {
                capturedPhoto = image
            }
        }
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.layoutPreviewLayer()
        if triggerCapture {
            uiView.capturePhoto()
            DispatchQueue.main.async { triggerCapture = false }
        }
    }
}

final class CameraPreviewUIView: UIView {
    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let output = AVCapturePhotoOutput()
    private let delegate = PhotoCaptureDelegate()
    var onCapture: ((UIImage) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        setupSession()

        let tap = UITapGestureRecognizer(target: self, action: #selector(capturePhoto))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupSession() {
        session.sessionPreset = .medium

        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func layoutPreviewLayer() {
        previewLayer.frame = bounds
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }

    @objc func capturePhoto() {
        guard session.isRunning else { return }
        delegate.completion = onCapture
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: delegate)
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    var completion: ((UIImage) -> Void)?

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        completion?(image)
    }
}
#else
struct CameraPreviewView: View {
    @Binding var capturedPhoto: NSImage?
    @Binding var triggerCapture: Bool
    init(capturedPhoto: Binding<NSImage?>, triggerCapture: Binding<Bool> = .constant(false)) {
        _capturedPhoto = capturedPhoto
        _triggerCapture = triggerCapture
    }
    var body: some View {
        Color.secondary.opacity(0.2)
            .overlay(Image(systemName: "camera.fill").foregroundStyle(.secondary))
    }
}
#endif
