//
//  TestSpeechEmotionsContentView.swift
//  CYT
//
//  Created by Carlos Mbendera on 14/02/2026.
//

import os
import SwiftUI

private let log = Logger(subsystem: "com.camysoftworks.dev.Test-Speech-Model", category: "UI")

struct TestSpeechEmotionsContentView: View {

    private let testFiles = ["neutral", "sad", "anger", "hap"]

    @State private var results: [String: EmotionPrediction] = [:]
    @State private var isLoading = false
    @State private var statusMessage: String = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Test Files") {
                    ForEach(testFiles, id: \.self) { file in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "waveform")
                                Text("\(file).wav")
                                    .font(.headline)
                            }

                            if let prediction = results[file] {
                                predictionView(prediction)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if isLoading {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Emotion Classifier")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await runClassification() }
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Label("Run", systemImage: "play.fill")
                        }
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                await runClassification()
            }
        }
    }

    private func predictionView(_ prediction: EmotionPrediction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(emojiFor(prediction.label))
                    .font(.title)
                Text(prediction.label.capitalized)
                    .font(.title3.bold())
                Spacer()
                Text(String(format: "%.1f%%", prediction.confidence * 100))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(prediction.allScores, id: \.label) { item in
                HStack {
                    Text(emojiFor(item.label))
                    Text(item.label.capitalized)
                        .font(.caption)
                        .frame(width: 60, alignment: .leading)
                    ProgressView(value: item.score.isNaN ? 0 : item.score)
                        .tint(colorFor(item.label))
                    Text(item.score.isNaN ? "—" : String(format: "%.1f%%", item.score * 100))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }

    private func runClassification() async {
        log.info("--- Classification started ---")
        isLoading = true
        errorMessage = nil
        statusMessage = "Compiling model for this device..."
        results = [:]

        do {
            // Use async loader — compiles model in background, avoids blocking on ANE compilation
            let classifier = try await SpeechEmotionClassifier.load()

            for file in testFiles {
                statusMessage = "Classifying \(file).wav..."
                log.info("Classifying: \(file).wav")

                let prediction = try await Task.detached {
                    try classifier.classify(wavResource: file)
                }.value

                results[file] = prediction
            }

            statusMessage = ""
            log.info("--- Classification complete, UI updated ---")
        } catch {
            log.error("--- Classification failed: \(error.localizedDescription) ---")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func emojiFor(_ label: String) -> String {
        switch label {
        case "angry": "😠"
        case "happy": "😊"
        case "neutral": "😐"
        case "sad": "😢"
        default: "❓"
        }
    }

    private func colorFor(_ label: String) -> Color {
        switch label {
        case "angry": .red
        case "happy": .yellow
        case "neutral": .blue
        case "sad": .purple
        default: .gray
        }
    }
}

#Preview {
    ContentView()
}
