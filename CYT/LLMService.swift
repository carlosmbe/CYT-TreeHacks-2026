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

    @Published private(set) var state: State = .idle

    private var generationTask: Task<String, Never>?
    private let ragService: RAGService?
#if canImport(FoundationModels)
    private var session: LanguageModelSession?
#endif

    init(ragService: RAGService? = LLMService.defaultRAGService()) {
        self.ragService = ragService
    }

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
                You are Lumen, a calm and supportive journaling assistant. \
                Do not provide diagnosis. Keep responses concise and practical.
                """
            )
            do {
                try await ragService?.loadIndex()
            } catch {
                state = .failed("RAG index load failed: \(error.localizedDescription)")
                return
            }
            state = .ready
        case .unavailable(let reason):
            state = .failed(unavailableMessage(for: reason))
        }
#else
        state = .failed("FoundationModels framework unavailable. Build with Xcode 26+ SDK.")
#endif
    }

    func generate(prompt: String) async -> String {
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
                let response = try await session.respond(to: cleanPrompt)
                return response.content
            } catch {
                return "Generation failed: \(error.localizedDescription)"
            }
        }
#else
        generationTask = Task<String, Never> {
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

    func generateWithRAG(
        query: String,
        searchConfig: RAGService.SearchConfig = .init()
    ) async -> String {
        guard let ragService else {
            return "RAG is not configured."
        }

        do {
            let hits = try await ragService.search(query: query, config: searchConfig)
            let groundedPrompt = await ragService.makeGroundedPrompt(query: query, hits: hits)
            return await generate(prompt: groundedPrompt)
        } catch {
            return "RAG retrieval failed: \(error.localizedDescription)"
        }
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

    private nonisolated static func defaultRAGService() -> RAGService {
        let dimension = 384
        return RAGService(
            embedder: CoreMLEmbedder(dimensions: dimension),
            index: BundledVectorIndex(dimension: dimension)
        )
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
