//
//  RAGStatusStore.swift
//  verso-reads
//

import Foundation
import Combine

@MainActor
final class RAGStatusStore: ObservableObject {
    static let shared = RAGStatusStore()

    @Published private(set) var indexingDocuments: Set<UUID> = []
    @Published private(set) var errorsByDocument: [UUID: String] = [:]

    func setIndexing(_ isIndexing: Bool, for documentID: UUID) {
        if isIndexing {
            indexingDocuments.insert(documentID)
        } else {
            indexingDocuments.remove(documentID)
        }
    }

    func setError(_ message: String?, for documentID: UUID) {
        if let message, message.isEmpty == false {
            errorsByDocument[documentID] = message
        } else {
            errorsByDocument.removeValue(forKey: documentID)
        }
    }

    func isIndexing(_ documentID: UUID) -> Bool {
        indexingDocuments.contains(documentID)
    }

    func errorMessage(for documentID: UUID) -> String? {
        errorsByDocument[documentID]
    }
}
