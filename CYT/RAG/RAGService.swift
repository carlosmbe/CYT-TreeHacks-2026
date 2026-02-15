import Foundation

/// Orchestrates retrieval-augmented generation using a pre-computed bundled
/// vector index and an on-device query embedder.
///
/// At startup, call `loadIndex()` to read the bundled index.
/// At query time, call `search(query:)` → `makeGroundedPrompt(query:hits:)`.
actor RAGService {
    struct SearchConfig: Sendable {
        var topK: Int = 3
        var minScore: Float = 0.25
    }

    private let embedder: TextEmbeddingProvider
    private let index: BundledVectorIndex

    init(
        embedder: TextEmbeddingProvider,
        index: BundledVectorIndex
    ) {
        self.embedder = embedder
        self.index = index
    }

    /// Load the pre-computed index from the app bundle. Call once at startup.
    func loadIndex() async throws {
        try await index.load()
    }

    /// Embed the query and search the index for relevant chunks.
    func search(query: String, config: SearchConfig = SearchConfig()) async throws -> [RAGSearchHit] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return [] }

        let queryVector = try await embedder.embed(text: cleanQuery)
        return await index.search(
            queryVector: queryVector,
            topK: config.topK,
            minScore: config.minScore
        )
    }

    /// Maximum character budget for the full grounded prompt.
    /// The on-device Foundation Model has a small context window;
    /// keeping prompts under this limit avoids "exceeded context" errors.
    /// Budget for the grounded prompt sent as the user turn.
    /// Reserve ~200 chars headroom for the LLMService session instructions (system prompt).
    private static let maxPromptChars = 2600

    /// Build a grounded prompt that includes retrieved context for the LLM.
    func makeGroundedPrompt(query: String, hits: [RAGSearchHit]) -> String {
        guard !hits.isEmpty else {
            return """
            User question:
            \(query)

            No retrieved context is available. Respond in the best way you can to aid the user. 
            """
        }

        // Build context incrementally, stopping before we exceed the budget.
        let preamble = """
        Answer using only the context below.

        Question: \(query)

        Context:

        """

        var contextParts: [String] = []
        var totalLen = preamble.count

        for (idx, hit) in hits.enumerated() {
            let part = "[\(idx + 1)] \(hit.chunk.text)"
            if totalLen + part.count + 2 > Self.maxPromptChars { break }
            contextParts.append(part)
            totalLen += part.count + 2 // +2 for newlines
        }

        return preamble + contextParts.joined(separator: "\n\n")
    }
}
