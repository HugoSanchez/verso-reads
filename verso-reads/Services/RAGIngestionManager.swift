//
//  RAGIngestionManager.swift
//  verso-reads
//

import Foundation

actor RAGIngestionManager {
    static let shared = RAGIngestionManager()

    private let store = RAGStore.shared
    private let embeddingModel = "text-embedding-3-small"

    func enqueue(document: LibraryDocument, fileURL: URL) async {
        await updateStatus(isIndexing: true, errorMessage: nil, documentID: document.id)

        do {
            let signature = try fileSignature(for: fileURL)
            if let existing = try await store.documentSignature(for: document.id), existing == signature {
                await updateStatus(isIndexing: false, errorMessage: nil, documentID: document.id)
                return
            }

            let apiKey = try await loadAPIKey()
            try await store.upsertDocument(document, signature: signature)
            try await store.clearEmbeddings(for: document.id)

            let pages = try await MainActor.run {
                try RAGTextExtractor.extractPages(from: fileURL)
            }
            let chunks = RAGChunker.chunk(pages: pages)

            guard chunks.isEmpty == false else {
                await updateStatus(isIndexing: false, errorMessage: "No extractable text found.", documentID: document.id)
                return
            }

            let embeddings = try await embedChunks(chunks, apiKey: apiKey)
            for (chunk, embeddingJSON) in embeddings {
                try await store.insertEmbedding(
                    documentID: document.id,
                    chunkIndex: chunk.chunkIndex,
                    pageStart: chunk.pageStart,
                    pageEnd: chunk.pageEnd,
                    text: chunk.text,
                    embeddingJSON: embeddingJSON
                )
            }

            await updateStatus(isIndexing: false, errorMessage: nil, documentID: document.id)
        } catch {
            await updateStatus(isIndexing: false, errorMessage: error.localizedDescription, documentID: document.id)
        }
    }

    func ensureIndexed(document: LibraryDocument, fileURL: URL) async {
        await enqueue(document: document, fileURL: fileURL)
    }

    private func embedChunks(_ chunks: [RAGChunk], apiKey: String) async throws -> [(RAGChunk, String)] {
        let batchSize = 16
        var results: [(RAGChunk, String)] = []

        var index = 0
        while index < chunks.count {
            let batch = Array(chunks[index..<min(index + batchSize, chunks.count)])
            let inputs = batch.map { $0.text }
            let embeddings = try await OpenAIClient(apiKey: apiKey, model: embeddingModel)
                .createEmbeddings(input: inputs, model: embeddingModel)

            for (chunk, embedding) in zip(batch, embeddings) {
                let json = try jsonString(from: embedding)
                results.append((chunk, json))
            }

            index += batchSize
        }

        return results
    }

    private func jsonString(from embedding: [Float]) throws -> String {
        let doubles = embedding.map { Double($0) }
        let data = try JSONSerialization.data(withJSONObject: doubles, options: [])
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func fileSignature(for url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? NSNumber
        let modifiedAt = attributes[.modificationDate] as? Date
        let sizeValue = fileSize?.int64Value ?? 0
        let modifiedValue = modifiedAt?.timeIntervalSince1970 ?? 0
        return "\(sizeValue)-\(modifiedValue)"
    }

    private func loadAPIKey() async throws -> String {
        try await MainActor.run {
            let bundleID = Bundle.main.bundleIdentifier ?? "verso-reads"
            let service = "\(bundleID).openai"
            let account = "openai-api-key"
            if let key = try KeychainStore.read(service: service, account: account),
               key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return key
            }
            throw NSError(domain: "RAG", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Missing OpenAI API key."
            ])
        }
    }

    private func updateStatus(isIndexing: Bool, errorMessage: String?, documentID: UUID) async {
        await MainActor.run {
            let store = RAGStatusStore.shared
            store.setIndexing(isIndexing, for: documentID)
            store.setError(errorMessage, for: documentID)
        }
    }
}
