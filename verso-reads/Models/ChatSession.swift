//
//  ChatSession.swift
//  verso-reads
//

import Foundation
import SwiftData

@Model
final class ChatSession {
    @Attribute(.unique) var id: UUID
    var documentID: UUID
    var createdAt: Date

    init(
        id: UUID = UUID(),
        documentID: UUID,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.documentID = documentID
        self.createdAt = createdAt
    }
}
