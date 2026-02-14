import AVFoundation
import CoreImage
import MLXLMCommon
import SwiftUI

struct VibeCheckView: View {
    @State private var camera = CameraController()
    @State private var model = FastVLMModel()
    @State private var framesToDisplay: AsyncStream<CVImageBuffer>?

    @State private var phase: VibePhase = .intro
    @State private var countdown = 3
    @State private var capturedFrame: CVImageBuffer?
    @State private var vlmOutput = ""
    @State private var detectedMood: MoodLevel = .neutral
    @State private var moodEmoji = ""

    var onComplete: (MoodLevel) -> Void

    enum VibePhase {
        case intro, scanning, analyzing, result
    }

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.08, blue: 0.25), Color(red: 0.12, green: 0.08, blue: 0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            switch phase {
            case .intro:
                introView
            case .scanning:
                scanningView
            case .analyzing:
                analyzingView
            case .result:
                resultView
            }
        }
        .task {
            await model.load()
        }
        .onAppear {
            // Start intro animation, then transition
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    phase = .scanning
                }
                startCamera()
                startCountdown()
            }
        }
    }

    // MARK: - Intro

    private var introView: some View {
        VStack(spacing: 24) {
            Image(systemName: "face.smiling")
                .font(.system(size: 80))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, options: .repeating)

            Text("Let's Check Your Vibe")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text("Hold still for a moment while we\nread your expression")
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            ProgressView()
                .tint(.white)
                .padding(.top)
        }
        .transition(.opacity)
    }

    // MARK: - Scanning

    private var scanningView: some View {
        VStack(spacing: 20) {
            Text("Reading your vibe...")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            ZStack {
                // Camera preview
                if let framesToDisplay {
                    VideoFrameView(
                        frames: framesToDisplay,
                        cameraType: .continuous,
                        action: nil
                    )
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(.white.opacity(0.3), lineWidth: 2)
                    )
                    .frame(maxHeight: 400)
                } else {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.white.opacity(0.1))
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .frame(maxHeight: 400)
                        .overlay(
                            ProgressView()
                                .tint(.white)
                        )
                }

                // Countdown overlay
                if countdown > 0 {
                    Text("\(countdown)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 10)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Text("Hold still...")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding()
        .transition(.opacity)
    }

    // MARK: - Analyzing

    private var analyzingView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 50))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, options: .repeating)
            }

            Text("Analyzing...")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            if !vlmOutput.isEmpty {
                Text(vlmOutput)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            ProgressView()
                .tint(.white)
        }
        .transition(.opacity)
    }

    // MARK: - Result

    private var resultView: some View {
        VStack(spacing: 24) {
            Text(detectedMood.emoji)
                .font(.system(size: 100))
                .shadow(color: .white.opacity(0.3), radius: 20)

            Text("You're feeling \(detectedMood.rawValue)")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            if !vlmOutput.isEmpty {
                Text(vlmOutput)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                onComplete(detectedMood)
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.white.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(.white.opacity(0.4), lineWidth: 1)
                            )
                    )
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)
        }
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Camera & VLM

    private func startCamera() {
        camera.backCamera = false
        camera.start()

        Task {
            let frames = AsyncStream<CMSampleBuffer>(bufferingPolicy: .bufferingNewest(1)) {
                camera.attach(continuation: $0)
            }

            let (displayFrames, displayContinuation) = AsyncStream.makeStream(
                of: CVImageBuffer.self,
                bufferingPolicy: .bufferingNewest(1)
            )
            self.framesToDisplay = displayFrames

            for await sampleBuffer in frames {
                if let frame = sampleBuffer.imageBuffer {
                    displayContinuation.yield(frame)
                    // Store latest frame for capture
                    self.capturedFrame = frame
                }
            }
            displayContinuation.finish()
        }
    }

    private func startCountdown() {
        countdown = 3
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if countdown > 1 {
                withAnimation(.spring(duration: 0.3)) {
                    countdown -= 1
                }
            } else {
                timer.invalidate()
                withAnimation {
                    countdown = 0
                }
                captureAndAnalyze()
            }
        }
    }

    private func captureAndAnalyze() {
        guard let frame = capturedFrame else {
            // No frame captured, use a fallback
            withAnimation(.easeInOut(duration: 0.5)) {
                detectedMood = .neutral
                vlmOutput = "Could not capture frame"
                phase = .result
            }
            return
        }

        withAnimation(.easeInOut(duration: 0.5)) {
            phase = .analyzing
        }

        camera.stop()

        let userInput = UserInput(
            prompt: .text("What is this person's facial expression and emotional state? Respond with one word for the mood, then a brief description."),
            images: [.ciImage(CIImage(cvPixelBuffer: frame))]
        )

        Task {
            let task = await model.generate(userInput)
            _ = await task.result

            let output = model.output
            vlmOutput = output
            detectedMood = mapToMood(output)

            withAnimation(.spring(duration: 0.6)) {
                phase = .result
            }
        }
    }

    private func mapToMood(_ text: String) -> MoodLevel {
        let lower = text.lowercased()
        if lower.contains("happy") || lower.contains("joy") || lower.contains("smile") || lower.contains("smiling") || lower.contains("cheerful") {
            return .happy
        } else if lower.contains("calm") || lower.contains("peaceful") || lower.contains("relaxed") || lower.contains("serene") {
            return .calm
        } else if lower.contains("stress") || lower.contains("tense") || lower.contains("frustrated") || lower.contains("angry") {
            return .stressed
        } else if lower.contains("anxious") || lower.contains("worried") || lower.contains("nervous") || lower.contains("fear") {
            return .anxious
        } else if lower.contains("sad") || lower.contains("unhappy") || lower.contains("down") || lower.contains("depress") {
            return .sad
        } else if lower.contains("neutral") || lower.contains("blank") || lower.contains("expressionless") {
            return .neutral
        }
        return .neutral
    }
}

#Preview {
    VibeCheckView { _ in }
}
