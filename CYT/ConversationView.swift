//
//  ConversationView.swift
//  CYT
//
//  Voice conversation with Lumen. Speech-to-text and emotion classification run in parallel.
//

import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String
    let content: String
    let timestamp: Date
}

@available(iOS 26.0, *)
struct ConversationView: View {
    @State private var viewModel = ConversationViewModel()
    @AppStorage("ttsEnabled") private var ttsEnabled = true

    var body: some View {
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

                Divider()

                HStack(spacing: 16) {
                    if viewModel.isRecording {
                        Button {
                            Task { await viewModel.stopAndProcess(ttsEnabled: ttsEnabled) }
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.red)
                        }
                        Text("Tap to stop")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            Task { await viewModel.startRecording() }
                        } label: {
                            Image(systemName: "mic.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(viewModel.canRecord ? .blue : .gray)
                        }
                        .disabled(!viewModel.canRecord)

                        if viewModel.isGenerating {
                            ProgressView()
                        }

                        Toggle("Lumen speaks", isOn: $ttsEnabled)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            .navigationTitle("Talk to Lumen")
            .navigationBarTitleDisplayMode(.inline)
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
            }
    }
}

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
                    .background(message.role == "user" ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if message.role == "assistant" {
                Spacer(minLength: 60)
            }
        }
    }
}

@available(iOS 26.0, *)
@Observable
final class ConversationViewModel {
    var messages: [ChatMessage] = []
    var isRecording = false
    var isGenerating = false
    var showAuthAlert = false
    var authAlertMessage = ""

    private let llmService = LLMService()
    private let speechRecognizer = SpeechRecognizer()
    private let emotionClassifier = EmotionClassifierService()
    private let textToSpeechService = TextToSpeechService()

    var canRecord: Bool {
        speechRecognizer.authorizationStatus == .authorized && !isGenerating
    }

    func requestAuthorization() {
        speechRecognizer.requestAuthorization()
    }

    func loadModel() async {
        await llmService.loadModel()
        await textToSpeechService.initialize()
    }

    func startRecording() async {
        guard !isRecording else { return }
        do {
            try speechRecognizer.startRecording()
            isRecording = true
        } catch SpeechRecognizerError.authorizationDenied {
            authAlertMessage = "Speech recognition was denied. Enable it in Settings to use voice."
            showAuthAlert = true
        } catch {
            authAlertMessage = error.localizedDescription
            showAuthAlert = true
        }
    }

    func stopAndProcess(ttsEnabled: Bool = true) async {
        guard isRecording else { return }
        isRecording = false
        isGenerating = true

        defer { isGenerating = false }

        do {
            let (transcript, audioURL) = try await speechRecognizer.stopRecording()

            guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }

            async let emotionTask: String? = emotionClassifier.classify(audioURL: audioURL)
            let emotion = await emotionTask

            let userContent = emotion.map { "\(transcript) (voice tone: \($0))" } ?? transcript
            messages.append(ChatMessage(role: "user", content: userContent, timestamp: Date()))

            let prompt = buildPrompt(latestUserMessage: transcript, emotion: emotion)
            let response = await llmService.generate(prompt: prompt)

            messages.append(ChatMessage(role: "assistant", content: response, timestamp: Date()))

            if ttsEnabled {
                await textToSpeechService.speak(text: response)
            }
        } catch {
            authAlertMessage = error.localizedDescription
            showAuthAlert = true
        }
    }

    private func buildPrompt(latestUserMessage: String, emotion: String?) -> String {
        let maxMessages = 6
        let recent = messages.suffix(maxMessages)
        var lines: [String] = []
        for msg in recent {
            let prefix = msg.role == "user" ? "User" : "Assistant"
            lines.append("\(prefix): \(msg.content)")
        }
        lines.append("Assistant:")
        return lines.joined(separator: "\n")
    }
}
