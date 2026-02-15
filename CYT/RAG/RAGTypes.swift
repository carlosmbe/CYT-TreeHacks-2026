import Foundation

struct RAGChunk: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let documentID: String
    let source: String
    let text: String
    let tokenStart: Int
    let tokenEnd: Int

    init(
        id: String = UUID().uuidString,
        documentID: String,
        source: String,
        text: String,
        tokenStart: Int,
        tokenEnd: Int
    ) {
        self.id = id
        self.documentID = documentID
        self.source = source
        self.text = text
        self.tokenStart = tokenStart
        self.tokenEnd = tokenEnd
    }
}

struct RAGSearchHit: Codable, Hashable, Sendable {
    let chunk: RAGChunk
    let score: Float
}
