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
    var markdown: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        documentID: UUID,
        markdown: String,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.documentID = documentID
        self.markdown = markdown
        self.updatedAt = updatedAt
    }
}
