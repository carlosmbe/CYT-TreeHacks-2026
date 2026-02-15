import Foundation

/// Protocol for on-device text embedding (used for query-time embedding only).
protocol TextEmbeddingProvider: Sendable {
    /// Embed one or more texts and return their vector representations.
    func embed(texts: [String]) async throws -> [[Float]]
}

extension TextEmbeddingProvider {
    /// Convenience: embed a single text.
    func embed(text: String) async throws -> [Float] {
        let vectors = try await embed(texts: [text])
        guard let first = vectors.first else {
            throw EmbeddingError.emptyResponse
        }
        return first
    }
}

enum EmbeddingError: Error, LocalizedError {
    case emptyResponse
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "Embedding model returned no vectors."
        case .modelNotLoaded:
            return "Core ML embedding model is not loaded."
        }
    }
}
