import Accelerate
import Foundation

/// Read-only vector index that loads a pre-computed index from the app bundle
/// and performs cosine-similarity search using SIMD-accelerated dot products.
actor BundledVectorIndex {
    struct Record: Codable {
        let chunk: RAGChunk
        let vector: [Float]
    }

    private let dimension: Int
    private let bundleResource: String
    private var records: [Record] = []

    /// - Parameters:
    ///   - dimension: Expected embedding dimension (must match the model used to build the index).
    ///   - bundleResource: Name of the JSON file in the app bundle (without extension).
    init(dimension: Int, bundleResource: String = "rag_index") {
        self.dimension = dimension
        self.bundleResource = bundleResource
    }

    /// Load the pre-computed index from the app bundle.
    func load() throws {
        guard let url = Bundle.main.url(forResource: bundleResource, withExtension: "json") else {
            throw BundledIndexError.resourceNotFound(bundleResource)
        }

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([Record].self, from: data)

        // Only keep records whose vectors match the expected dimension.
        records = decoded.filter { $0.vector.count == dimension }

        if records.count != decoded.count {
            print("[RAG] Warning: dropped \(decoded.count - records.count) record(s) with mismatched dimension.")
        }
        print("[RAG] Loaded \(records.count) pre-computed chunk(s) from bundle.")
    }

    /// Search the index for the top-K nearest chunks to `queryVector`.
    func search(queryVector: [Float], topK: Int, minScore: Float) -> [RAGSearchHit] {
        guard !records.isEmpty, queryVector.count == dimension, topK > 0 else {
            return []
        }

        let normalizedQuery = l2Normalize(queryVector)

        let hits: [RAGSearchHit] = records.compactMap { record in
            let score = vDSP.dot(normalizedQuery, record.vector)
            guard score >= minScore else { return nil }
            return RAGSearchHit(chunk: record.chunk, score: score)
        }

        return Array(
            hits.sorted { $0.score > $1.score }
                .prefix(topK)
        )
    }

    // MARK: - Private

    private func l2Normalize(_ vector: [Float]) -> [Float] {
        var sumSquares: Float = 0
        vDSP_svesq(vector, 1, &sumSquares, vDSP_Length(vector.count))
        guard sumSquares > 0 else { return vector }
        let norm = sqrt(sumSquares)
        return vector.map { $0 / norm }
    }
}

enum BundledIndexError: Error, LocalizedError {
    case resourceNotFound(String)

    var errorDescription: String? {
        switch self {
        case .resourceNotFound(let name):
            return "RAG index resource '\(name).json' not found in app bundle."
        }
    }
}
