//
//  ChatMessageRecord.swift
//  verso-reads
//

import Foundation
import SwiftData

@Model
final class ChatMessageRecord {
    @Attribute(.unique) var id: UUID
    var documentID: UUID
    var chatSessionID: UUID?
    var roleRawValue: String
    var content: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        documentID: UUID,
        chatSessionID: UUID? = nil,
        role: ChatMessage.Role,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.documentID = documentID
        self.chatSessionID = chatSessionID
        self.roleRawValue = role == .user ? "user" : "assistant"
        self.content = content
        self.createdAt = createdAt
    }
}
