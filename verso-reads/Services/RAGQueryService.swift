//
//  RAGQueryService.swift
//  verso-reads
//

import Foundation

struct RAGQueryService {
    static let shared = RAGQueryService()

    private let embeddingModel = "text-embedding-3-small"

    func retrieveContext(
        documentID: UUID,
        query: String,
        apiKey: String,
        maxChunks: Int = 4
    ) async throws -> String? {
        let client = OpenAIClient(apiKey: apiKey, model: embeddingModel)
        let embeddings = try await client.createEmbeddings(input: [query], model: embeddingModel)
        guard let embedding = embeddings.first else { return nil }
        let embeddingJSON = try jsonString(from: embedding)

        let results = try await RAGStore.shared.searchSimilar(
            documentID: documentID,
            embeddingJSON: embeddingJSON,
            limit: maxChunks
        )

        guard results.isEmpty == false else { return nil }
        return format(results: results)
    }

    private func format(results: [RAGStore.RAGChunkResult]) -> String {
        results.enumerated().map { index, result in
            let label: String
            if let start = result.pageStart, let end = result.pageEnd, start != end {
                label = "Page \(start)-\(end)"
            } else if let start = result.pageStart {
                label = "Page \(start)"
            } else {
                label = "Section \(index + 1)"
            }
            return "\(label):\n\(result.text)"
        }.joined(separator: "\n\n")
    }

    private func jsonString(from embedding: [Float]) throws -> String {
        let doubles = embedding.map { Double($0) }
        let data = try JSONSerialization.data(withJSONObject: doubles, options: [])
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
