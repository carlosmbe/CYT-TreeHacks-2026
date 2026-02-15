//
//  LLMService.swift
//  CYT
//
//

import Foundation
internal import Combine
#if canImport(FoundationModels)
import FoundationModels
#endif

@available(iOS 26.0, *)
@MainActor
final class LLMService: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case ready
        case generating
        case failed(String)
    }

    struct GenerationConfig {
        var maxNewTokens: Int = 256
        var temperature: Float = 0.7
    }

    @Published private(set) var state: State = .idle

    private var generationTask: Task<String, Never>?
#if canImport(FoundationModels)
    private var session: LanguageModelSession?
#endif

    func loadModel() async {
        if case .loading = state {
            return
        }

        state = .loading
#if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            session = LanguageModelSession(
                instructions: """
                You are Lumen, a calm and supportive care companion. \
                You receive biometric signals (heart rate, HRV, sleep), voice emotion, and facial analysis. \
                Write a short, warm personal note (2-3 sentences) acknowledging how the person feels. \
                Then list 3-4 ACTION lines, each: ACTION: category | title | one-line reason. \
                Categories: breathe, music, connect, move, express, rest, celebrate. \
                Never diagnose. Be concise — you have limited space.
                """
            )
            state = .ready
        case .unavailable(let reason):
            state = .failed(unavailableMessage(for: reason))
        }
#else
        state = .failed("FoundationModels framework unavailable. Build with Xcode 26+ SDK.")
#endif
    }

    func generate(prompt: String) async -> String {
        await generate(prompt: prompt, config: GenerationConfig())
    }

    func generate(prompt: String, config: GenerationConfig) async -> String {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else {
            return ""
        }

        guard case .ready = state else {
            return "Model is not ready yet. Tap Load first."
        }

        generationTask?.cancel()
        state = .generating

#if canImport(FoundationModels)
        generationTask = Task<String, Never> {
            guard let session else {
                return "Foundation model session is unavailable."
            }

            do {
                _ = config
                let response = try await session.respond(to: cleanPrompt)
                return response.content
            } catch {
                return "Generation failed: \(error.localizedDescription)"
            }
        }
#else
        generationTask = Task<String, Never> {
            _ = config
            return "FoundationModels framework unavailable in this SDK."
        }
#endif

        let output = await generationTask?.value ?? ""
        generationTask = nil
        if case .generating = state {
            state = .ready
        }
        return output
    }

    func cancel() {
        generationTask?.cancel()
        generationTask = nil
        if case .failed = state {
            return
        }
        state = hasLoadedSession ? .ready : .idle
    }

    private var hasLoadedSession: Bool {
#if canImport(FoundationModels)
        return session != nil
#else
        return false
#endif
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private func unavailableMessage(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
    switch reason {
    case .deviceNotEligible:
        return "This device does not support Apple Intelligence."
    case .appleIntelligenceNotEnabled:
        return "Enable Apple Intelligence in Settings."
    case .modelNotReady:
        return "Foundation model is downloading/preparing. Try again later."
    default:
        return "Foundation model unavailable: \(String(describing: reason))"
    }
}
#endif
