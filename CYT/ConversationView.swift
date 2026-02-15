//
//  ConversationView.swift
//  CYT
//
//  Mic-first, orb-based conversation experience.
//  STT + emotion classification -> LLM -> TTS.
//  Centered orb/ring with waveform during recording, glowing orb when Vera speaks.
//  Side drawer cards, text mode toggle, animated gradient with ripple transition.
//

import SwiftUI
import ActivityKit
import AVKit
import os

// MARK: - Chat Message

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String      // "user" or "assistant"
    let content: String
    let timestamp: Date
    var emotion: String?  // detected emotion for this turn
}

// MARK: - Conversation State

enum ConversationState: Equatable {
    case idle
    case recording
    case processing
    case veraSpeaking
    case paused
}

// MARK: - Conversation View

@available(iOS 26.0, *)
struct ConversationView: View {
    @State private var viewModel = ConversationViewModel()
    @AppStorage("ttsEnabled") private var ttsEnabled = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var showSummary = false
    @State private var textMode = false

    var body: some View {
        ZStack {
            // Background: starts white, ripples to mood color
            AnimatedGradientBackground(
                mood: viewModel.currentMood,
                hasMoodDetected: viewModel.hasMoodDetected
            )

            VStack(spacing: 0) {
                // Top status strip
                statusStrip

                // Top toolbar
                topToolbar

                // Main content
                if textMode {
                    textModeView
                } else {
                    voiceModeView
                }
            }

            // PiP host (invisible, must be in view hierarchy)
            PiPHostView(pipService: viewModel.pipService)
                .frame(width: 1, height: 1)
                .opacity(0.01)

            // Side drawer cards
            FloatingCardStack(
                cards: viewModel.visibleCards,
                onTapCard: { card in handleCardTap(card) },
                onDismissCard: { card in viewModel.dismissCard(card) }
            )
        }
        .navigationBarHidden(true)
        .alert("Speech Recognition", isPresented: $viewModel.showAuthAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.authAlertMessage)
        }
        .task {
            viewModel.requestAuthorization()
            await viewModel.loadModel()
            await viewModel.fetchHealthData()
            viewModel.startLiveActivity()
            // Allow hostView to settle in hierarchy before configuring PiP
            try? await Task.sleep(for: .milliseconds(500))
            viewModel.pipService.configure()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .inactive:
                // Start PiP proactively during transition to background
                if viewModel.conversationState != .idle && !viewModel.pipService.userDismissedPiP {
                    viewModel.pipService.startPiP()
                }
            case .background:
                viewModel.updateLiveActivity()
                if viewModel.conversationState != .idle && !viewModel.pipService.userDismissedPiP && !viewModel.pipService.isPiPActive {
                    viewModel.pipService.startPiP()
                }
            case .active:
                if viewModel.pipService.isPiPActive {
                    viewModel.pipService.stopPiP()
                }
                viewModel.pipService.resetDismissFlag()
            @unknown default:
                break
            }
        }
        .navigationDestination(isPresented: $showSummary) {
            if let summary = viewModel.conversationSummary {
                ConversationSummaryView(summary: summary) {
                    viewModel.resetConversation()
                    showSummary = false
                }
            }
        }
        .navigationDestination(for: CardCategory.self) { _ in
            JournalEntryView(
                package: CarePackage(
                    personalNote: viewModel.messages.last(where: { $0.role == "assistant" })?.content ?? "Reflect on your conversation with Vera.",
                    cards: viewModel.suggestedCards,
                    djSession: DJSession(moodLabel: "", genre: "", tracks: []),
                    signals: CheckInSignals(emotionLabel: viewModel.currentMood, emotionConfidence: 0.8, facialAnalysis: "", healthSnapshot: HealthSnapshot()),
                    followUpQuestion: "",
                    timestamp: Date()
                )
            )
        }
    }

    // MARK: - Status Strip

    private var statusStrip: some View {
        Rectangle()
            .fill(statusStripColor)
            .frame(height: 3)
            .opacity(viewModel.conversationState == .recording ? 1.0 : 0.4)
            .animation(
                viewModel.conversationState == .recording
                    ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                    : .default,
                value: viewModel.conversationState
            )
    }

    private var statusStripColor: LinearGradient {
        switch viewModel.conversationState {
        case .recording:
            return LinearGradient(colors: [.red.opacity(0.8), .orange.opacity(0.6), .red.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
        case .processing:
            return LinearGradient(colors: [.blue.opacity(0.5), .purple.opacity(0.4)], startPoint: .leading, endPoint: .trailing)
        case .veraSpeaking:
            return LinearGradient(colors: [.green.opacity(0.5), .cyan.opacity(0.4)], startPoint: .leading, endPoint: .trailing)
        case .idle, .paused:
            return LinearGradient(colors: [.gray.opacity(0.2), .gray.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
        }
    }

    // MARK: - Top Toolbar

    private var topToolbar: some View {
        HStack {
            // Text mode toggle
            Button {
                withAnimation(.spring(response: 0.3)) {
                    textMode.toggle()
                }
            } label: {
                Image(systemName: textMode ? "waveform" : "text.bubble")
                    .font(.body)
                    .foregroundStyle(viewModel.hasMoodDetected ? .white.opacity(0.8) : .primary.opacity(0.6))
                    .padding(8)
                    .background(.ultraThinMaterial.opacity(0.5))
                    .clipShape(Circle())
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: - Voice Mode (default)

    private var voiceModeView: some View {
        VStack(spacing: 0) {
            Spacer()

            // Orb / Ring
            orbView
                .padding(.bottom, 16)

            // Status text
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(viewModel.hasMoodDetected ? .white.opacity(0.7) : .secondary)
                .animation(.easeInOut(duration: 0.3), value: viewModel.conversationState)

            // Action buttons below status
            HStack(spacing: 16) {
                // Skip button when Vera is speaking
                if viewModel.conversationState == .veraSpeaking {
                    Button {
                        viewModel.skipSpeaking()
                    } label: {
                        Label("Skip", systemImage: "forward.fill")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(viewModel.hasMoodDetected ? .white.opacity(0.8) : Color(white: 0.3))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial.opacity(0.6))
                            .clipShape(Capsule())
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Pause/Resume button
                if viewModel.conversationState == .recording || viewModel.conversationState == .paused {
                    Button {
                        if viewModel.conversationState == .paused {
                            Task { await viewModel.resumeConversation(ttsEnabled: ttsEnabled) }
                        } else {
                            viewModel.pauseConversation()
                        }
                    } label: {
                        Label(
                            viewModel.conversationState == .paused ? "Resume" : "Pause",
                            systemImage: viewModel.conversationState == .paused ? "play.fill" : "pause.fill"
                        )
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(viewModel.hasMoodDetected ? .white.opacity(0.8) : Color(white: 0.3))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial.opacity(0.6))
                            .clipShape(Capsule())
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Send / process recording button
                if viewModel.conversationState == .recording {
                    Button {
                        Task { await viewModel.stopAndGenerate() }
                    } label: {
                        Label("Send", systemImage: "arrow.up.circle.fill")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(viewModel.hasMoodDetected ? .white.opacity(0.9) : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial.opacity(0.6))
                            .clipShape(Capsule())
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.top, 12)
            .animation(.easeInOut(duration: 0.25), value: viewModel.conversationState)

            Spacer()

            // End Conversation button at the bottom
            if viewModel.messages.count >= 1 {
                Button {
                    Task {
                        await viewModel.endExchange()
                        showSummary = true
                    }
                } label: {
                    Label("End Conversation", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(viewModel.hasMoodDetected ? .white.opacity(0.7) : .secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial.opacity(0.4))
                        .clipShape(Capsule())
                }
                .padding(.bottom, 24)
                .transition(.opacity)
            }
        }
    }

    private var statusText: String {
        switch viewModel.conversationState {
        case .idle:
            return "Tap to talk to Vera"
        case .recording:
            return "Listening..."
        case .processing:
            return "Vera is thinking..."
        case .veraSpeaking:
            return "Vera is speaking..."
        case .paused:
            return "Paused"
        }
    }

    // MARK: - Orb View

    private var orbView: some View {
        ZStack {
            switch viewModel.conversationState {
            case .idle:
                idleMicButton
            case .recording:
                waveformRing
            case .processing:
                processingRing
            case .veraSpeaking:
                glowingOrb
            case .paused:
                pausedOrb
            }
        }
        .frame(width: 160, height: 160)
        .contentShape(Circle())
        .onTapGesture {
            if viewModel.conversationState == .idle {
                Task { await viewModel.startRecording(ttsEnabled: ttsEnabled) }
            } else if viewModel.conversationState == .paused {
                Task { await viewModel.resumeConversation(ttsEnabled: ttsEnabled) }
            }
        }
    }

    private var idleMicButton: some View {
        ZStack {
            Circle()
                .fill(viewModel.hasMoodDetected ? .ultraThinMaterial : .regularMaterial)
                .frame(width: 120, height: 120)
                .shadow(color: .black.opacity(0.12), radius: 20, y: 4)

            Image(systemName: "mic.fill")
                .font(.system(size: 40))
                .foregroundStyle(viewModel.hasMoodDetected ? .white : Color(white: 0.25))
        }
    }

    private var pausedOrb: some View {
        ZStack {
            Circle()
                .fill(viewModel.hasMoodDetected ? .ultraThinMaterial : .regularMaterial)
                .frame(width: 120, height: 120)
                .shadow(color: .black.opacity(0.12), radius: 20, y: 4)

            Image(systemName: "play.fill")
                .font(.system(size: 36))
                .foregroundStyle(viewModel.hasMoodDetected ? .white.opacity(0.8) : Color(white: 0.3))
        }
    }

    private var waveformRing: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let amp = CGFloat(viewModel.audioAmplitude)

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let baseRadius: CGFloat = 50
                let segments = 64

                var path = Path()
                for i in 0...segments {
                    let angle = (CGFloat(i) / CGFloat(segments)) * .pi * 2
                    let wave = sin(angle * 6 + CGFloat(t) * 5) * amp * 25
                    let noise = sin(angle * 3 + CGFloat(t) * 3.5) * amp * 15
                    let spike = sin(angle * 12 + CGFloat(t) * 7) * amp * 8
                    let r = baseRadius + wave + noise + spike + amp * 18
                    let point = CGPoint(
                        x: center.x + cos(angle) * r,
                        y: center.y + sin(angle) * r
                    )
                    if i == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
                path.closeSubpath()

                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [.red.opacity(0.8), .orange.opacity(0.6), .red.opacity(0.8)]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: size.width, y: size.height)
                    ),
                    lineWidth: 3
                )

                context.stroke(
                    path,
                    with: .color(.red.opacity(0.15)),
                    lineWidth: 8
                )
            }

            Image(systemName: "mic.fill")
                .font(.system(size: 28))
                .foregroundStyle(.red.opacity(0.9))
        }
    }

    private var processingRing: some View {
        ZStack {
            Circle()
                .stroke(Color.blue.opacity(0.3), lineWidth: 3)
                .frame(width: 90, height: 90)
                .scaleEffect(1.0)
                .overlay(
                    Circle()
                        .stroke(Color.blue.opacity(0.15), lineWidth: 6)
                        .frame(width: 90, height: 90)
                        .scaleEffect(1.15)
                        .opacity(0.6)
                )

            ProgressView()
                .scaleEffect(1.2)
                .tint(viewModel.hasMoodDetected ? .white : .primary)
        }
        .transition(.scale.combined(with: .opacity))
    }

    private var glowingOrb: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                moodOrbColor.opacity(0.4),
                                moodOrbColor.opacity(0.1),
                                .clear
                            ],
                            center: .center,
                            startRadius: 30,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .scaleEffect(1.0 + CGFloat(sin(t * 1.5)) * 0.08)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                moodOrbColor.opacity(0.9),
                                moodOrbColor.opacity(0.5),
                                moodOrbColor.opacity(0.2)
                            ],
                            center: .center,
                            startRadius: 5,
                            endRadius: 45
                        )
                    )
                    .frame(width: 80, height: 80)
                    .scaleEffect(1.0 + CGFloat(sin(t * 2.0)) * 0.06)
                    .shadow(color: moodOrbColor.opacity(0.4), radius: 20)

                Image(systemName: "waveform")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var moodOrbColor: Color {
        switch viewModel.currentMood.lowercased() {
        case "sad": return .blue
        case "angry": return .red
        case "happy": return .yellow
        default: return .cyan
        }
    }

    // MARK: - Text Mode

    private var textModeView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let last = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Compact orb at bottom in text mode
            HStack(spacing: 12) {
                Spacer()
                compactOrb
                    .frame(width: 60, height: 60)
                    .onTapGesture {
                        if viewModel.conversationState == .idle {
                            Task { await viewModel.startRecording(ttsEnabled: ttsEnabled) }
                        } else if viewModel.conversationState == .paused {
                            Task { await viewModel.resumeConversation(ttsEnabled: ttsEnabled) }
                        }
                    }
                if viewModel.conversationState == .veraSpeaking {
                    Button {
                        viewModel.skipSpeaking()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.body)
                            .foregroundStyle(viewModel.hasMoodDetected ? .white.opacity(0.8) : Color(white: 0.3))
                            .padding(10)
                            .background(.ultraThinMaterial.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .transition(.opacity)
                }
                if viewModel.conversationState == .recording || viewModel.conversationState == .paused {
                    Button {
                        if viewModel.conversationState == .paused {
                            Task { await viewModel.resumeConversation(ttsEnabled: ttsEnabled) }
                        } else {
                            viewModel.pauseConversation()
                        }
                    } label: {
                        Image(systemName: viewModel.conversationState == .paused ? "play.fill" : "pause.fill")
                            .font(.body)
                            .foregroundStyle(viewModel.hasMoodDetected ? .white.opacity(0.8) : Color(white: 0.3))
                            .padding(10)
                            .background(.ultraThinMaterial.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .transition(.opacity)

                    if viewModel.conversationState == .recording {
                        Button {
                            Task { await viewModel.stopAndGenerate() }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.body)
                                .foregroundStyle(viewModel.hasMoodDetected ? .white.opacity(0.9) : .primary)
                                .padding(10)
                                .background(.ultraThinMaterial.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .transition(.opacity)
                    }
                }
                Spacer()
            }
            .padding(.bottom, 12)

            // End Conversation button at the bottom in text mode too
            if viewModel.messages.count >= 1 {
                Button {
                    Task {
                        await viewModel.endExchange()
                        showSummary = true
                    }
                } label: {
                    Label("End Conversation", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(viewModel.hasMoodDetected ? .white.opacity(0.7) : .secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial.opacity(0.4))
                        .clipShape(Capsule())
                }
                .padding(.bottom, 12)
            }
        }
    }

    private var compactOrb: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)

            switch viewModel.conversationState {
            case .idle:
                Image(systemName: "mic.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(viewModel.hasMoodDetected ? .white : Color(white: 0.25))
            case .recording:
                Image(systemName: "mic.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse)
            case .processing:
                ProgressView()
                    .scaleEffect(0.8)
            case .veraSpeaking:
                Image(systemName: "waveform")
                    .font(.system(size: 18))
                    .foregroundStyle(moodOrbColor)
                    .symbolEffect(.variableColor.iterative)
            case .paused:
                Image(systemName: "play.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(viewModel.hasMoodDetected ? .white.opacity(0.8) : Color(white: 0.3))
            }
        }
    }

    // MARK: - Card Actions

    private func handleCardTap(_ card: CarePackageCard) {
        switch card.category {
        case .breathe, .rest:
            if let url = URL(string: "x-apple-health://") {
                openURL(url)
            }
        case .connect:
            if let url = URL(string: "tel://") {
                openURL(url)
            }
        case .move:
            if let url = URL(string: "x-apple-health://") {
                openURL(url)
            }
        case .music:
            let term = "relaxing music".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "music://search?term=\(term)") {
                openURL(url)
            }
        case .celebrate:
            break
        case .express:
            break
        }
        viewModel.dismissCard(card)
    }
}

// MARK: - PiP Host View (UIKit bridge)

@available(iOS 26.0, *)
private struct PiPHostView: UIViewRepresentable {
    let pipService: PiPService

    func makeUIView(context: Context) -> UIView {
        pipService.hostView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer(minLength: 60)
            }
            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            if message.role == "assistant" {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Conversation Summary (result of End Exchange)

struct ConversationSummary {
    var veraNote: String
    var cards: [CarePackageCard]
    var djSession: DJSession
    var mood: String
    var messageCount: Int
    var healthSnapshot: HealthSnapshot
}

// MARK: - Conversation View Model

@available(iOS 26.0, *)
@Observable
final class ConversationViewModel {
    var messages: [ChatMessage] = []
    var isRecording = false
    var isGenerating = false
    var isSpeaking = false
    var isPaused = false
    var showAuthAlert = false
    var authAlertMessage = ""
    var currentMood: String = "neutral"
    var suggestedCards: [CarePackageCard] = []
    var visibleCards: [CarePackageCard] = []
    var conversationSummary: ConversationSummary?
    var audioAmplitude: Float = 0
    var hasMoodDetected = false

    var latestCardColor: Color? {
        visibleCards.last?.color
    }

    var conversationState: ConversationState {
        if isPaused { return .paused }
        if isSpeaking { return .veraSpeaking }
        if isGenerating { return .processing }
        if isRecording { return .recording }
        return .idle
    }

    let pipService = PiPService()
    private let llmService = LLMService()
    private let speechRecognizer = SpeechRecognizer()
    private let emotionClassifier = EmotionClassifierService()
    private let textToSpeechService = TextToSpeechService()
    private let healthProvider = HealthDataProvider()
    private var healthSnapshot = HealthSnapshot()
    private var sessionStartDate = Date()
    private var emotionHistory: [String] = []
    private var ttsEnabledForSession = true
    private var liveActivity: Activity<ConversationActivityAttributes>?
    private var lastAlertedCardID: UUID?
    private var turnCount = 0
    private var amplitudeThrottleTimer: Timer?
    private static let logger = Logger(subsystem: "com.cyt.vera", category: "Conversation")

    var canRecord: Bool {
        speechRecognizer.authorizationStatus == .authorized && !isGenerating && !isSpeaking
    }

    // MARK: - Setup

    func requestAuthorization() {
        speechRecognizer.requestAuthorization()
    }

    func loadModel() async {
        await llmService.loadModel()
        await textToSpeechService.initialize()
    }

    func fetchHealthData() async {
        healthSnapshot = await healthProvider.fetchSnapshot()
    }

    // MARK: - Recording

    func startRecording(ttsEnabled: Bool = true) async {
        guard !isRecording, !isPaused else { return }
        self.ttsEnabledForSession = ttsEnabled
        speechRecognizer.onEndOfSpeechDetected = { [weak self] in
            await self?.handleAutoStop()
        }
        speechRecognizer.onAmplitudeUpdate = { [weak self] amplitude in
            Task { @MainActor in
                self?.audioAmplitude = amplitude
            }
        }
        do {
            try speechRecognizer.startRecording()
            isRecording = true
            sessionStartDate = Date()
            startAmplitudeThrottle()
            updateLiveActivity()
            syncPiPState()
        } catch SpeechRecognizerError.authorizationDenied {
            authAlertMessage = "Speech recognition was denied. Enable it in Settings to use voice."
            showAuthAlert = true
        } catch {
            authAlertMessage = error.localizedDescription
            showAuthAlert = true
        }
    }

    // MARK: - Stop Recording & Process

    /// Stops recording and immediately processes the transcript (generates AI response).
    func stopAndGenerate() async {
        guard isRecording else { return }
        Self.logger.info("Manual stop — processing transcript")
        // Trigger the same flow as silence-detected auto-stop
        await stopAndProcess(ttsEnabled: ttsEnabledForSession)
    }

    // MARK: - Pause / Resume

    func pauseConversation() {
        guard isRecording else { return }
        speechRecognizer.cancelRecording()
        isRecording = false
        isPaused = true
        audioAmplitude = 0
        stopAmplitudeThrottle()
        updateLiveActivity()
        syncPiPState()
        Self.logger.info("Conversation paused")
    }

    func resumeConversation(ttsEnabled: Bool = true) async {
        guard isPaused else { return }
        isPaused = false
        await startRecording(ttsEnabled: ttsEnabled)
        Self.logger.info("Conversation resumed")
    }

    private func handleAutoStop() async {
        await stopAndProcess(ttsEnabled: ttsEnabledForSession)
    }

    private func stopAndProcess(ttsEnabled: Bool = true) async {
        guard isRecording else { return }
        isRecording = false
        audioAmplitude = 0
        stopAmplitudeThrottle()

        do {
            let (transcript, audioURL) = try await speechRecognizer.stopRecording()

            guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                // Empty transcript — restart recording
                if !isPaused {
                    await startRecording(ttsEnabled: ttsEnabledForSession)
                }
                return
            }

            await processTranscript(transcript, audioURL: audioURL, ttsEnabled: ttsEnabled)
        } catch {
            authAlertMessage = error.localizedDescription
            showAuthAlert = true
        }
    }

    /// Process a completed turn (emotion classification + LLM + TTS). Must be called on foreground.
    private func processTranscript(_ transcript: String, audioURL: URL, ttsEnabled: Bool) async {
        isGenerating = true
        turnCount += 1
        let currentTurn = turnCount
        syncPiPState()

        defer {
            isGenerating = false
            isSpeaking = false
            syncPiPState()
        }

        async let emotionTask: String? = emotionClassifier.classify(audioURL: audioURL)
        let emotion = await emotionTask

        if let emotion {
            emotionHistory.append(emotion)
            currentMood = emotion
            if !hasMoodDetected {
                hasMoodDetected = true
            }
            syncPiPState()
        }

        Self.logger.info("[Turn \(currentTurn)] Emotion: \(emotion ?? "none"), Mood: \(self.currentMood), hasMoodDetected: \(self.hasMoodDetected)")

        let userContent = emotion.map { "\(transcript) (voice tone: \($0))" } ?? transcript
        messages.append(ChatMessage(role: "user", content: userContent, timestamp: Date(), emotion: emotion))

            // Send to LLM — the KV cache preserves the full conversation history,
            // so we only send the new user message (no need to rebuild old turns).
            let response = await llmService.chat(userMessage: userContent)

        messages.append(ChatMessage(role: "assistant", content: response, timestamp: Date()))

        evaluateCardSuggestions(emotion: emotion, transcript: transcript)

        Self.logger.info("[Turn \(currentTurn)] Response length: \(response.count), Cards: \(self.visibleCards.count)")

        if ttsEnabled {
            isSpeaking = true
            isGenerating = false
            syncPiPState()
            await textToSpeechService.speak(text: response, interruptible: true)
            isSpeaking = false
            syncPiPState()

            Self.logger.info("[Turn \(currentTurn)] TTS complete, state: \(String(describing: self.conversationState))")

            if !isRecording && !isPaused {
                await startRecording(ttsEnabled: ttsEnabledForSession)
            }
        } else if !isPaused {
            await startRecording(ttsEnabled: ttsEnabledForSession)
        }
    }

    // MARK: - Skip Speaking

    func skipSpeaking() {
        guard isSpeaking else { return }
        textToSpeechService.stop()
        isSpeaking = false
        syncPiPState()
    }

    // MARK: - Card Suggestion Engine

    private func evaluateCardSuggestions(emotion: String?, transcript: String) {
        let alreadySuggested = Set(suggestedCards.map(\.category))
        let messageCount = messages.count / 2 // conversation turns

        // Sad → connect
        let sadCount = emotionHistory.filter { $0 == "sad" }.count
        if sadCount >= 2, !alreadySuggested.contains(.connect) {
            suggest(CarePackageCard(title: "Call Someone", subtitle: "A familiar voice helps", category: .connect))
        }

        // Angry → express (journal)
        if emotion == "angry", !alreadySuggested.contains(.express) {
            suggest(CarePackageCard(title: "Write It Out", subtitle: "Get it off your chest", category: .express))
        }

        // Low HRV → breathe
        if let hrv = healthSnapshot.hrv, hrv < 30, !alreadySuggested.contains(.breathe) {
            suggest(CarePackageCard(title: "Breathe With Me", subtitle: "Your HRV is low", category: .breathe))
        }

        // Low sleep → rest
        if let sleep = healthSnapshot.sleepHours, sleep < 5, !alreadySuggested.contains(.rest) {
            suggest(CarePackageCard(title: "Rest Mode", subtitle: "You need more sleep", category: .rest))
        }

        // Mentions exercise/walk → move
        let lowerTranscript = transcript.lowercased()
        if (lowerTranscript.contains("walk") || lowerTranscript.contains("exercise") || lowerTranscript.contains("run")),
           !alreadySuggested.contains(.move) {
            suggest(CarePackageCard(title: "Get Moving", subtitle: "Fresh air does wonders", category: .move))
        }

        // Happy + good vitals → celebrate
        let happyCount = emotionHistory.filter { $0 == "happy" }.count
        if happyCount >= 2, !alreadySuggested.contains(.celebrate) {
            suggest(CarePackageCard(title: "Celebrate!", subtitle: "You're in a great place", category: .celebrate))
        }

        // After 3+ exchanges → music
        if messageCount >= 3, !alreadySuggested.contains(.music) {
            suggest(CarePackageCard(title: "DJ Session", subtitle: "Music for your mood", category: .music))
        }

        // If first turn and neutral — suggest breathe as a gentle start
        if messageCount == 1, emotion == "neutral", suggestedCards.isEmpty {
            suggest(CarePackageCard(title: "Take a Breath", subtitle: "Center yourself", category: .breathe))
        }
    }

    private func suggest(_ card: CarePackageCard) {
        suggestedCards.append(card)
        visibleCards.append(card)
        updateLiveActivity()
        syncPiPState()
    }

    func dismissCard(_ card: CarePackageCard) {
        visibleCards.removeAll { $0.id == card.id }
    }

    // MARK: - End Exchange

    func endExchange() async {
        if isRecording {
            speechRecognizer.cancelRecording()
            isRecording = false
        }
        isPaused = false
        speechRecognizer.stopInterruptMonitoring()
        textToSpeechService.stop()
        isSpeaking = false
        audioAmplitude = 0
        stopAmplitudeThrottle()

        // Generate summary via LLM
        let healthContext = HealthDataProvider.formatForLLM(healthSnapshot)
        let summaryNote = await llmService.generateSummary(
            messages: messages,
            cards: suggestedCards,
            healthContext: healthContext
        )

        let mood = dominantMood()
        conversationSummary = ConversationSummary(
            veraNote: summaryNote,
            cards: suggestedCards,
            djSession: djSessionForMood(mood),
            mood: mood,
            messageCount: messages.count,
            healthSnapshot: healthSnapshot
        )

        endLiveActivity()
        pipService.stopPiP()
    }

    func resetConversation() {
        messages = []
        suggestedCards = []
        visibleCards = []
        emotionHistory = []
        currentMood = "neutral"
        conversationSummary = nil
        isGenerating = false
        isSpeaking = false
        isPaused = false
        audioAmplitude = 0
        hasMoodDetected = false
        lastAlertedCardID = nil
        turnCount = 0
    }

    private func dominantMood() -> String {
        guard !emotionHistory.isEmpty else { return "neutral" }
        var counts: [String: Int] = [:]
        for e in emotionHistory { counts[e, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? "neutral"
    }

    private func djSessionForMood(_ mood: String) -> DJSession {
        switch mood {
        case "sad":
            return DJSession(moodLabel: "Gentle & Comforting", genre: "Acoustic", tracks: [
                DJTrack(title: "Better Days", artist: "OneRepublic"),
                DJTrack(title: "Breathe Me", artist: "Sia"),
                DJTrack(title: "Fix You", artist: "Coldplay"),
            ])
        case "angry":
            return DJSession(moodLabel: "Channel the Energy", genre: "Rock", tracks: [
                DJTrack(title: "Lose Yourself", artist: "Eminem"),
                DJTrack(title: "Stronger", artist: "Kanye West"),
                DJTrack(title: "Eye of the Tiger", artist: "Survivor"),
            ])
        case "happy":
            return DJSession(moodLabel: "Keep the Vibes", genre: "Pop", tracks: [
                DJTrack(title: "Happy", artist: "Pharrell"),
                DJTrack(title: "Good as Hell", artist: "Lizzo"),
                DJTrack(title: "Walking on Sunshine", artist: "Katrina & The Waves"),
            ])
        default:
            return DJSession(moodLabel: "Calm & Reflective", genre: "Lo-fi", tracks: [
                DJTrack(title: "Weightless", artist: "Marconi Union"),
                DJTrack(title: "Clair de Lune", artist: "Debussy"),
                DJTrack(title: "Intro", artist: "The xx"),
            ])
        }
    }

    
    // MARK: - Live Activity

    func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = ConversationActivityAttributes(sessionStart: Date())
        let state = ConversationActivityAttributes.ContentState(
            isRecording: false,
            latestCardTitle: nil,
            latestCardIcon: nil,
            moodColor: "neutral",
            audioLevel: 0
        )
        do {
            liveActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            // Live Activity not available
        }
    }

    func updateLiveActivity() {
        guard let liveActivity else { return }
        let latestCard = visibleCards.last

        let level = amplitudeToLevel(audioAmplitude)
        let state = ConversationActivityAttributes.ContentState(
            isRecording: isRecording,
            latestCardTitle: latestCard?.title,
            latestCardIcon: latestCard?.sfSymbol,
            moodColor: currentMood,
            audioLevel: level
        )

        // Only alert for NEW cards
        let shouldAlert = latestCard != nil && latestCard?.id != lastAlertedCardID
        if shouldAlert {
            lastAlertedCardID = latestCard?.id
        }

        Self.logger.info("LiveActivity update — recording: \(self.isRecording), mood: \(self.currentMood), card: \(latestCard?.title ?? "none"), audioLevel: \(level)")

        Task {
            let alertConfig = shouldAlert
                ? AlertConfiguration(title: "\(latestCard!.title)", body: "\(latestCard!.subtitle)", sound: .default)
                : nil

            await liveActivity.update(
                ActivityContent(state: state, staleDate: nil),
                alertConfiguration: alertConfig
            )
        }
    }

    func endLiveActivity() {
        guard let liveActivity else { return }
        let finalState = ConversationActivityAttributes.ContentState(
            isRecording: false,
            latestCardTitle: "Session ended",
            latestCardIcon: "checkmark.circle",
            moodColor: currentMood,
            audioLevel: 0
        )
        Task {
            await liveActivity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .after(.now + 30)
            )
        }
        self.liveActivity = nil
    }

    func endConversation() {
        if isRecording {
            speechRecognizer.cancelRecording()
            isRecording = false
        }
        isPaused = false
        speechRecognizer.stopInterruptMonitoring()
        textToSpeechService.stop()
        isSpeaking = false
        stopAmplitudeThrottle()
        endLiveActivity()
        pipService.stopPiP()
        
      
        Task { await llmService.resetConversation() }
        
        resetConversation()
              
    }

    // MARK: - Amplitude Throttle for Live Activity

    private func startAmplitudeThrottle() {
        stopAmplitudeThrottle()
        amplitudeThrottleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateLiveActivity()
                self?.syncPiPState()
            }
        }
    }

    private func stopAmplitudeThrottle() {
        amplitudeThrottleTimer?.invalidate()
        amplitudeThrottleTimer = nil
    }

    private func amplitudeToLevel(_ amplitude: Float) -> Int {
        switch amplitude {
        case ..<0.05: return 0
        case 0.05..<0.25: return 1
        case 0.25..<0.55: return 2
        default: return 3
        }
    }

    // MARK: - PiP State Sync

    private func syncPiPState() {
        pipService.isRecording = isRecording
        pipService.audioLevel = amplitudeToLevel(audioAmplitude)
        pipService.moodColor = currentMood
        pipService.sessionStart = sessionStartDate
        pipService.latestCardTitle = visibleCards.last?.title
        pipService.latestCardIcon = visibleCards.last?.sfSymbol

        if isPaused {
            pipService.statusText = "Paused"
        } else if isSpeaking {
            pipService.statusText = "Vera is speaking..."
        } else if isGenerating {
            pipService.statusText = "Thinking..."
        } else if isRecording {
            pipService.statusText = "Listening..."
        } else {
            pipService.statusText = "Tap to talk"
        }

        pipService.setNeedsRender()
    }
}
