//
//  ChatMessage.swift
//  verso-reads
//

import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var content: String
    var sourceAnchorData: Data?
    var sourceSelectionText: String?
    var promptMessageID: UUID?

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        sourceAnchorData: Data? = nil,
        sourceSelectionText: String? = nil,
        promptMessageID: UUID? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.sourceAnchorData = sourceAnchorData
        self.sourceSelectionText = sourceSelectionText
        self.promptMessageID = promptMessageID
    }
}
