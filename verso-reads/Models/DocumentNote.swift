//
//  DocumentNote.swift
//  verso-reads
//

import Foundation
import SwiftData

@Model
final class DocumentNote {
    @Attribute(.unique) var id: UUID
    var documentID: UUID
    var content: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        documentID: UUID,
        content: String,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.documentID = documentID
        self.content = content
        self.updatedAt = updatedAt
    }
}
