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
                You are Vera, a calm and supportive conversational assistant. \
                Ask reflective questions. Do not diagnose. Keep responses warm and concise. \ 
                YOU HAVE TO HELP THE USER IF THEY ARE GOING THROUGH A HARD TIME, IF THEY NEED REAL HELP, SEND THEM TO A PROFESSIONAL.
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

    /// Generates a summary note from the full conversation and suggested cards.
    func generateSummary(messages: [ChatMessage], cards: [CarePackageCard], healthContext: String) async -> String {
        var promptLines: [String] = []
        promptLines.append("Summarize this conversation in 2-3 warm sentences as Vera. Include what was discussed, how the user seemed to feel, and any self-care suggestions that were offered.")
        promptLines.append("")

        if !healthContext.isEmpty {
            promptLines.append("Health context: \(healthContext)")
            promptLines.append("")
        }

        if !cards.isEmpty {
            let cardNames = cards.map { "\($0.title) (\($0.category.rawValue))" }.joined(separator: ", ")
            promptLines.append("Cards suggested: \(cardNames)")
            promptLines.append("")
        }

        promptLines.append("Conversation:")
        for msg in messages {
            let prefix = msg.role == "user" ? "User" : "Vera"
            promptLines.append("\(prefix): \(msg.content)")
        }
        promptLines.append("")
        promptLines.append("Write Vera's summary note:")

        let prompt = promptLines.joined(separator: "\n")
        return await generate(prompt: prompt)
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
