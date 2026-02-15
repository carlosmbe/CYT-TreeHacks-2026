import Foundation

/// Orchestrates retrieval-augmented generation using a pre-computed bundled
/// vector index and an on-device query embedder.
///
/// At startup, call `loadIndex()` to read the bundled index.
/// At query time, call `search(query:)` → `makeContextSnippet(hits:maxChars:)`.
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

    /// Build a context-only snippet from RAG hits, budget-capped to `maxChars`.
    /// Used for multi-turn chat where the user message and conversation history
    /// are handled separately by the KV cache.
    /// Returns `nil` if no hits pass the budget.
    func makeContextSnippet(hits: [RAGSearchHit], maxChars: Int) -> String? {
        guard !hits.isEmpty else { return nil }

        var parts: [String] = []
        var totalLen = 0

        for (idx, hit) in hits.enumerated() {
            let part = "[\(idx + 1)] \(hit.chunk.text)"
            if totalLen + part.count + 2 > maxChars { break }
            parts.append(part)
            totalLen += part.count + 2
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n\n")
    }
}
