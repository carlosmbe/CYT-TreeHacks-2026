//
//  LLMService.swift
//  CYT
//
//  On-device LLM using NVIDIA Nemotron-Mini-4B-Instruct via llama.cpp.
//

import Foundation
import Combine

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

    /// The llama.cpp context (non-Sendable – run on a background serial queue).
    private var llamaContext: LlamaContext?

    /// Tracks the current turn number in the conversation (0 = first turn).
    /// Used for adaptive RAG budgeting: turn 0 gets a larger budget for richer grounding.
    private var chatTurnCount = 0

    /// System instructions for "Vera", the wellness assistant.
    private let systemPrompt = """
    You are Vera. You talk like a thoughtful, curious friend — not a therapist and not a chatbot. \
    Your main job is to LISTEN and ASK GOOD QUESTIONS. You are trying to understand this person, not fix them. \
    Keep responses nice, conversational, and concise 2-3 sentences. End responses with a genuine question that digs deeper into what they just said when you deem fit. \
    Do NOT lecture. Do NOT list generic advice. Do NOT repeat back what they said in fancier words. \
    When you do share advice, keep it to to a few specific ideas and explain it well. Only share advice after you've asked enough to understand their situation. \
    Use what they've already told you. Reference specific things they said earlier. \
    Match their tone — casual if they're casual, serious if they're serious. \
    If they mention self-harm or suicide, take it seriously and tell them about the 988 Suicide & Crisis Lifeline. \
    Do not diagnose. Be real, be curious, be a good friend.
    """

    /// Name of the GGUF file bundled in the app.
    private static let modelFileName = "nemotron-mini-4b-instruct-q4_k_m"
    private static let modelFileExtension = "gguf"

    init(ragService: RAGService? = LLMService.defaultRAGService()) {
        self.ragService = ragService
    }

    // MARK: - Load

    func loadModel() async {
        if case .loading = state { return }
        state = .loading

        // Locate the bundled GGUF model.
        guard let modelPath = Bundle.main.path(
            forResource: Self.modelFileName,
            ofType: Self.modelFileExtension
        ) else {
            state = .failed(
                "Model file \(Self.modelFileName).\(Self.modelFileExtension) not found in bundle. " +
                "Run scripts/download_nemotron.sh and add the file to Xcode."
            )
            return
        }

        // Load llama.cpp model on a background thread (heavy I/O).
        do {
            let ctx = try await Task.detached(priority: .userInitiated) {
                try LlamaContext.create(path: modelPath)
            }.value

            self.llamaContext = ctx
            print("[LLMService] Model loaded: \(ctx.modelInfo())")

            // Initialize the conversation with the system prompt so the KV cache
            // is primed and ready for the first user message.
            let sysPrompt = systemPrompt
            await Task.detached(priority: .userInitiated) {
                ctx.startConversation(systemPrompt: sysPrompt)
            }.value

            // Load RAG index.
            try await ragService?.loadIndex()

            state = .ready
        } catch {
            state = .failed("Model load failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Multi-turn chat (with RAG)

    /// Send a user message and get the assistant's response.
    /// Each turn:
    ///   1. Embeds the user message and searches the RAG index for relevant chunks
    ///   2. Injects the retrieved context into the turn alongside the user message
    ///   3. Generates a response with the full conversation history in the KV cache
    ///
    /// Adaptive RAG budget:
    ///   - Turn 0 (first message): 3000 chars — fits all 3 chunks for rich grounding
    ///   - Subsequent turns: min(1800, remainingChars / 5) — tapers off to leave
    ///     more room for conversation history
    func chat(userMessage: String) async -> String {
        let cleanMessage = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanMessage.isEmpty else { return "" }
        guard case .ready = state else {
            return "Model is not ready yet. Tap Load first."
        }

        generationTask?.cancel()
        state = .generating

        let ctx = llamaContext

        // RAG retrieval with adaptive budget based on turn number.
        var ragSnippet: String?
        if let ragService, let ctx {
            do {
                let hits = try await ragService.search(query: cleanMessage)
                let remainingChars = Int(ctx.remainingTokens) * 4

                let ragBudget: Int
                if chatTurnCount == 0 {
                    // First turn: 3000 chars — room for all 3 chunks (~1000 chars each)
                    ragBudget = min(remainingChars, 3000)
                } else {
                    // Subsequent turns: 1800 cap or 20% of remaining, whichever is smaller
                    ragBudget = min(1800, remainingChars / 5)
                }

                print("[LLMService] RAG: turn=\(chatTurnCount), hits=\(hits.count), budget=\(ragBudget) chars")
                for (i, hit) in hits.enumerated() {
                    print("[LLMService] RAG hit[\(i)]: score=\(hit.score), source=\(hit.chunk.source), text=\(hit.chunk.text.prefix(80))...")
                }

                ragSnippet = await ragService.makeContextSnippet(hits: hits, maxChars: ragBudget)

                if let snippet = ragSnippet {
                    print("[LLMService] RAG snippet injected: \(snippet.count) chars")
                } else {
                    print("[LLMService] RAG snippet: nil (no hits fit budget)")
                }
            } catch {
                print("[LLMService] RAG retrieval FAILED: \(error.localizedDescription)")
            }
        } else {
            print("[LLMService] RAG skipped: ragService=\(ragService != nil), ctx=\(ctx != nil)")
        }

        let snippet = ragSnippet

        generationTask = Task<String, Never> {
            guard let ctx else {
                return "Llama context is unavailable."
            }

            let result = await Task.detached(priority: .userInitiated) {
                ctx.respondToUser(message: cleanMessage, ragContext: snippet)
            }.value

            return result
        }

        let output = await generationTask?.value ?? ""
        generationTask = nil
        chatTurnCount += 1
        if case .generating = state {
            state = .ready
        }
        return output
    }

    /// Reset the conversation context. Call when the user ends a conversation
    /// or wants to start fresh. Re-primes the KV cache with the system prompt.
    func resetConversation() async {
        chatTurnCount = 0
        let ctx = llamaContext
        let sysPrompt = systemPrompt
        await Task.detached(priority: .userInitiated) {
            ctx?.startConversation(systemPrompt: sysPrompt)
        }.value
    }

    // MARK: - Cancel

    func cancel() {
        generationTask?.cancel()
        generationTask = nil
        if case .failed = state { return }
        state = llamaContext != nil ? .ready : .idle
    }

    // MARK: - Helpers

    private nonisolated static func defaultRAGService() -> RAGService {
        let dimension = 384
        return RAGService(
            embedder: CoreMLEmbedder(dimensions: dimension),
            index: BundledVectorIndex(dimension: dimension)
        )
    }
}
