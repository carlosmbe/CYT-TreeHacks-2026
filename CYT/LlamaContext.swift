//
//  LlamaContext.swift
//  CYT
//
//  Swift wrapper around llama.cpp for on-device NVIDIA Nemotron-Mini-4B inference.
//  Based on the official llama.cpp SwiftUI example (ggml-org/llama.cpp).
//

import Foundation
import LlamaSwift

enum LlamaError: Error, LocalizedError {
    case modelLoadFailed(String)
    case contextCreationFailed
    case decodeFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path):
            return "Failed to load model at \(path)"
        case .contextCreationFailed:
            return "Failed to create llama context"
        case .decodeFailed:
            return "Token decode failed"
        case .cancelled:
            return "Generation was cancelled"
        }
    }
}

// MARK: - Batch helpers

private func llama_batch_clear(_ batch: inout llama_batch) {
    batch.n_tokens = 0
}

private func llama_batch_add(
    _ batch: inout llama_batch,
    _ id: llama_token,
    _ pos: llama_pos,
    _ seq_ids: [llama_seq_id],
    _ logits: Bool
) {
    batch.token   [Int(batch.n_tokens)] = id
    batch.pos     [Int(batch.n_tokens)] = pos
    batch.n_seq_id[Int(batch.n_tokens)] = Int32(seq_ids.count)
    for i in 0..<seq_ids.count {
        batch.seq_id[Int(batch.n_tokens)]![i] = seq_ids[i]
    }
    batch.logits  [Int(batch.n_tokens)] = logits ? 1 : 0
    batch.n_tokens += 1
}

// MARK: - LlamaContext

/// Thread-unsafe – always call from the same serial context (e.g. an actor).
final class LlamaContext {

    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private var sampling: UnsafeMutablePointer<llama_sampler>
    private var batch: llama_batch
    private var temporaryInvalidCChars: [CChar] = []

    /// Current position in the KV cache (total tokens processed so far).
    private(set) var nCur: Int32 = 0

    /// Number of tokens generated in the current response.
    private var nGenerated: Int32 = 0

    private(set) var isDone = false

    /// Maximum tokens to generate per single response.
    var maxTokens: Int32 = 512

    /// The system prompt stored for context-overflow recovery.
    private var activeSystemPrompt: String?

    // MARK: Init / Deinit

    private init(model: OpaquePointer, context: OpaquePointer) {
        self.model = model
        self.context = context
        self.vocab = llama_model_get_vocab(model)
        self.batch = llama_batch_init(4096, 0, 1)

        let sparams = llama_sampler_chain_default_params()
        self.sampling = llama_sampler_chain_init(sparams)!
        // Temperature 0.7 for more natural, conversational responses
        llama_sampler_chain_add(self.sampling, llama_sampler_init_temp(0.7))
        llama_sampler_chain_add(self.sampling, llama_sampler_init_dist(1234))
    }

    deinit {
        llama_sampler_free(sampling)
        llama_batch_free(batch)
        llama_model_free(model)
        llama_free(context)
        llama_backend_free()
    }

    // MARK: Factory

    /// Load a GGUF model from `path`. Call once at startup.
    static func create(path: String) throws -> LlamaContext {
        llama_backend_init()

        var modelParams = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
        print("[LlamaContext] Simulator detected – GPU layers disabled")
        #endif

        guard let model = llama_model_load_from_file(path, modelParams) else {
            throw LlamaError.modelLoadFailed(path)
        }

        let nThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        print("[LlamaContext] Using \(nThreads) threads")

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = 4096      // Full Nemotron-Mini-4B context window
        ctxParams.n_threads       = Int32(nThreads)
        ctxParams.n_threads_batch = Int32(nThreads)

        guard let ctx = llama_init_from_model(model, ctxParams) else {
            llama_model_free(model)
            throw LlamaError.contextCreationFailed
        }

        return LlamaContext(model: model, context: ctx)
    }

    // MARK: - Context info

    /// Total context window size.
    var contextSize: Int32 { Int32(llama_n_ctx(context)) }

    /// How many tokens of context are still available.
    var remainingTokens: Int32 { contextSize - nCur }

    // MARK: - Multi-turn conversation

    /// Start a new conversation. Clears all previous state and feeds the system prompt
    /// into the KV cache. Call once when the user opens the chat.
    func startConversation(systemPrompt: String) {
        clear()
        activeSystemPrompt = systemPrompt
        let text = "<extra_id_0>System\n\(systemPrompt)\n"
        feedTokens(text: text, addBOS: true)
        print("[LlamaContext] Conversation started – \(nCur) tokens used for system prompt, \(remainingTokens) remaining")
    }

    /// Add a user message and generate the assistant's response.
    /// The KV cache is preserved between calls so the model remembers the full
    /// conversation history — no re-processing of old turns.
    ///
    /// - Parameters:
    ///   - message: The user's message text.
    ///   - ragContext: Optional RAG-retrieved context to ground the response.
    ///                 When provided, it's injected into the user turn so the model
    ///                 can reference it alongside the conversation history.
    func respondToUser(message: String, ragContext: String? = nil) -> String {
        // Format the new user turn, optionally including RAG context
        let userTurnBody: String
        if let ctx = ragContext {
            userTurnBody = """
            [Reference context:
            \(ctx)]

            \(message)
            """
        } else {
            userTurnBody = message
        }

        let turnText = "<extra_id_1>User\n\(userTurnBody)\n<extra_id_1>Assistant\n"
        let turnTokens = tokenize(text: turnText, addBOS: false)

        // Check if we have room for the new turn + a full response
        let needed = Int32(turnTokens.count) + maxTokens
        if nCur + needed > contextSize {
            print("[LlamaContext] Context window full (\(nCur)/\(contextSize)). Restarting conversation.")
            if let sys = activeSystemPrompt {
                startConversation(systemPrompt: sys)
            } else {
                clear()
            }
        }

        // Feed the user turn into the KV cache
        feedTokens(text: turnText, addBOS: false)

        // Generate the assistant's response token-by-token
        isDone = false
        nGenerated = 0
        temporaryInvalidCChars = []

        var output = ""
        while !isDone {
            output += completionStep()
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        print("[LlamaContext] Generated \(nGenerated) tokens – \(nCur)/\(contextSize) context used (\(remainingTokens) remaining)")
        return trimmed
    }

    // MARK: - State management

    /// Clear KV cache and all state. Starts completely fresh.
    func clear() {
        temporaryInvalidCChars.removeAll()
        nCur = 0
        nGenerated = 0
        isDone = false
        llama_memory_clear(llama_get_memory(context), true)
    }

    // MARK: - Model info

    func modelInfo() -> String {
        let buf = UnsafeMutablePointer<CChar>.allocate(capacity: 256)
        buf.initialize(repeating: 0, count: 256)
        defer { buf.deallocate() }

        let n = llama_model_desc(model, buf, 256)
        let bufferPointer = UnsafeBufferPointer(start: buf, count: Int(n))
        return String(bufferPointer.map { Character(UnicodeScalar(UInt8($0))) })
    }

    // MARK: - Internal helpers

    /// Feed tokens into the KV cache without generating (for prompts / user turns).
    private func feedTokens(text: String, addBOS: Bool) {
        let tokens = tokenize(text: text, addBOS: addBOS)

        llama_batch_clear(&batch)
        for (i, token) in tokens.enumerated() {
            let isLast = (i == tokens.count - 1)
            llama_batch_add(&batch, token, nCur + Int32(i), [0], isLast)
        }

        if llama_decode(context, batch) != 0 {
            print("[LlamaContext] feedTokens decode failed")
        }

        nCur += Int32(tokens.count)
    }

    /// Sample and decode one token. Called in a loop during response generation.
    private func completionStep() -> String {
        let newTokenID = llama_sampler_sample(sampling, context, batch.n_tokens - 1)

        if llama_vocab_is_eog(vocab, newTokenID) || nGenerated >= maxTokens {
            isDone = true
            let trailing = String(cString: temporaryInvalidCChars + [0])
            temporaryInvalidCChars.removeAll()
            return trailing
        }

        let newTokenCChars = tokenToPiece(token: newTokenID)
        temporaryInvalidCChars.append(contentsOf: newTokenCChars)

        let newTokenStr: String
        if let valid = String(validatingUTF8: temporaryInvalidCChars + [0]) {
            temporaryInvalidCChars.removeAll()
            newTokenStr = valid
        } else if (0..<temporaryInvalidCChars.count).contains(where: {
            $0 != 0 && String(validatingUTF8: Array(temporaryInvalidCChars.suffix($0)) + [0]) != nil
        }) {
            let s = String(cString: temporaryInvalidCChars + [0])
            temporaryInvalidCChars.removeAll()
            newTokenStr = s
        } else {
            newTokenStr = ""
        }

        llama_batch_clear(&batch)
        llama_batch_add(&batch, newTokenID, nCur, [0], true)

        nCur += 1
        nGenerated += 1

        if llama_decode(context, batch) != 0 {
            print("[LlamaContext] completionStep decode failed")
        }

        return newTokenStr
    }

    // MARK: - Tokenization

    private func tokenize(text: String, addBOS: Bool) -> [llama_token] {
        let utf8Count = text.utf8.count
        let nTokens = utf8Count + (addBOS ? 1 : 0) + 1
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: nTokens)
        defer { tokens.deallocate() }

        let count = llama_tokenize(vocab, text, Int32(utf8Count), tokens, Int32(nTokens), addBOS, true)
        return (0..<Int(count)).map { tokens[$0] }
    }

    private func tokenToPiece(token: llama_token) -> [CChar] {
        let buf = UnsafeMutablePointer<CChar>.allocate(capacity: 8)
        buf.initialize(repeating: 0, count: 8)
        defer { buf.deallocate() }

        let n = llama_token_to_piece(vocab, token, buf, 8, 0, false)

        if n < 0 {
            let bigger = UnsafeMutablePointer<CChar>.allocate(capacity: Int(-n))
            bigger.initialize(repeating: 0, count: Int(-n))
            defer { bigger.deallocate() }

            let n2 = llama_token_to_piece(vocab, token, bigger, -n, 0, false)
            return Array(UnsafeBufferPointer(start: bigger, count: Int(n2)))
        } else {
            return Array(UnsafeBufferPointer(start: buf, count: Int(n)))
        }
    }
}
