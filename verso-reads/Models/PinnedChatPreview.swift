//
//  PinnedChatPreview.swift
//  verso-reads
//

import Foundation

struct PinnedChatPreview: Identifiable, Equatable {
    let id: UUID
    let assistantMessageID: UUID
    let assistantText: String
    let userText: String?
    let anchorData: Data?
}
