import Accelerate
import CoreML
import Foundation
import Hub
import Tokenizers

/// On-device query embedder using a Core ML sentence-transformer model.
///
/// Setup:
/// 1. Run `scripts/export_coreml_embedder.py` to produce `MiniLMEmbedder.mlpackage`.
/// 2. Drag it into the Xcode project (target: CYT) and build once.
/// 3. Xcode generates Swift classes: `MiniLMEmbedder`, `MiniLMEmbedderInput`, `MiniLMEmbedderOutput`.
/// 4. Add `rag_index.json` to the Xcode project as a bundle resource.
///
/// The model must be the **same** one used by `scripts/build_rag_index.py`
/// so that query vectors live in the same embedding space as the pre-computed
/// document vectors.
final class CoreMLEmbedder: TextEmbeddingProvider, @unchecked Sendable {
    let dimensions: Int
    let maxTokens: Int

    private let lock = NSLock()
    private var cachedModel: MiniLMEmbedder?
    private var cachedTokenizer: (any Tokenizer)?

    init(dimensions: Int = 384, maxTokens: Int = 256) {
        self.dimensions = dimensions
        self.maxTokens = maxTokens
    }

    func embed(texts: [String]) async throws -> [[Float]] {
        let tokenizer = try loadTokenizer()
        let model = try loadModel()

        return try texts.map { text in
            // 1. Tokenize -- swift-transformers adds [CLS] and [SEP] automatically
            let encoded = tokenizer(text)
            let tokenIDs = encoded.map { Int32($0) }

            // 2. Pad or truncate to fixed maxTokens length
            let (inputIDs, attentionMask) = padOrTruncate(tokenIDs: tokenIDs)

            // 3. Build MLMultiArray inputs
            let inputIDsArray = try createMLMultiArray(from: inputIDs)
            let maskArray = try createMLMultiArray(from: attentionMask)

            // 4. Run Core ML inference
            let input = MiniLMEmbedderInput(
                input_ids: inputIDsArray,
                attention_mask: maskArray
            )
            let output = try model.prediction(input: input)

            // 5. Extract last_hidden_state as flat [Float]
            //    Shape: (1, maxTokens, dimensions)
            let hiddenState = extractFloats(from: output.last_hidden_state)

            // 6. Mean-pool over token dimension using attention mask
            let pooled = Self.meanPool(
                hiddenState: hiddenState,
                mask: attentionMask,
                hiddenDim: dimensions,
                seqLen: maxTokens
            )

            // 7. L2-normalize so dot product == cosine similarity
            return Self.l2Normalize(pooled)
        }
    }

    // MARK: - Lazy Loading

    private func loadModel() throws -> MiniLMEmbedder {
        try lock.withLock {
            if let model = cachedModel { return model }
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let model = try MiniLMEmbedder(configuration: config)
            cachedModel = model
            return model
        }
    }

    private func loadTokenizer() throws -> any Tokenizer {
        if let tokenizer = lock.withLock({ cachedTokenizer }) {
            return tokenizer
        }

        // Load bundled tokenizer JSON files directly into Config objects.
        // Files are renamed (minilm_ prefix) to avoid collision with FastVLM's
        // tokenizer files in the app bundle.
        guard let dataURL = Bundle.main.url(forResource: "minilm_tokenizer", withExtension: "json"),
              let configURL = Bundle.main.url(forResource: "minilm_tokenizer_config", withExtension: "json") else {
            throw EmbeddingError.modelNotLoaded
        }

        let tokenizerData = try parseJSONConfig(from: dataURL)
        let tokenizerConfig = try parseJSONConfig(from: configURL)

        let tokenizer = try AutoTokenizer.from(
            tokenizerConfig: tokenizerConfig,
            tokenizerData: tokenizerData
        )
        lock.withLock { cachedTokenizer = tokenizer }
        return tokenizer
    }

    /// Parse a JSON file into a Hub.Config object.
    private func parseJSONConfig(from url: URL) throws -> Config {
        let data = try Data(contentsOf: url)
        guard let parsed = try JSONSerialization.jsonObject(with: data) as? [NSString: Any] else {
            throw EmbeddingError.modelNotLoaded
        }
        return Config(parsed)
    }

    // MARK: - Tokenization Helpers

    /// Pad short sequences with zeros or truncate long ones to `maxTokens`.
    private func padOrTruncate(tokenIDs: [Int32]) -> (inputIDs: [Int32], attentionMask: [Int32]) {
        let len = min(tokenIDs.count, maxTokens)
        var ids = Array(tokenIDs.prefix(len))
        var mask = [Int32](repeating: 1, count: len)

        if len < maxTokens {
            ids += [Int32](repeating: 0, count: maxTokens - len)
            mask += [Int32](repeating: 0, count: maxTokens - len)
        }

        return (ids, mask)
    }

    /// Create an MLMultiArray of shape (1, maxTokens) from Int32 values.
    private func createMLMultiArray(from values: [Int32]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: maxTokens)], dataType: .int32)
        for (i, v) in values.enumerated() {
            array[i] = NSNumber(value: v)
        }
        return array
    }

    /// Extract all values from an MLMultiArray as [Float], handling Float16/Float32.
    private func extractFloats(from multiArray: MLMultiArray) -> [Float] {
        let count = multiArray.count
        switch multiArray.dataType {
        case .float32:
            let ptr = multiArray.dataPointer.bindMemory(to: Float.self, capacity: count)
            return Array(UnsafeBufferPointer(start: ptr, count: count))
        case .float16:
            let ptr = multiArray.dataPointer.bindMemory(to: Float16.self, capacity: count)
            return (0..<count).map { Float(ptr[$0]) }
        default:
            return (0..<count).map { multiArray[$0].floatValue }
        }
    }

    // MARK: - Pooling & Normalization

    /// L2-normalize a vector using Accelerate.
    static func l2Normalize(_ vector: [Float]) -> [Float] {
        var sumSquares: Float = 0
        vDSP_svesq(vector, 1, &sumSquares, vDSP_Length(vector.count))
        guard sumSquares > 0 else { return vector }
        let norm = sqrt(sumSquares)
        return vector.map { $0 / norm }
    }

    /// Mean-pool hidden states over the token dimension, masked by attention_mask.
    /// - Parameters:
    ///   - hiddenState: Flat Float array of shape (1, seqLen, hiddenDim).
    ///   - mask: Int32 attention mask of shape (1, seqLen). 1 = real token, 0 = padding.
    ///   - hiddenDim: The embedding dimension.
    ///   - seqLen: Sequence length (maxTokens).
    static func meanPool(
        hiddenState: [Float],
        mask: [Int32],
        hiddenDim: Int,
        seqLen: Int
    ) -> [Float] {
        var pooled = [Float](repeating: 0, count: hiddenDim)
        var tokenCount: Float = 0

        for t in 0..<seqLen {
            guard mask[t] == 1 else { continue }
            tokenCount += 1
            let offset = t * hiddenDim
            for d in 0..<hiddenDim {
                pooled[d] += hiddenState[offset + d]
            }
        }

        guard tokenCount > 0 else { return pooled }
        return pooled.map { $0 / tokenCount }
    }
}
