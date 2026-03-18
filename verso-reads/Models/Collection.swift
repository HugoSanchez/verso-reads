//
//  Collection.swift
//  verso-reads
//

import Foundation
import SwiftData

@Model
final class DocumentCollection {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var documentIDs: [UUID]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.documentIDs = []
    }

    func addDocument(_ documentID: UUID) {
        guard documentIDs.contains(documentID) == false else { return }
        documentIDs.append(documentID)
    }

    func removeDocument(_ documentID: UUID) {
        documentIDs.removeAll { $0 == documentID }
    }
}
