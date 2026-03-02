//
//  ChatContext.swift
//  verso-reads
//

import Foundation

struct ChatContext: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let wordCount: Int
    let anchorData: Data?

    init(text: String, anchorData: Data? = nil) {
        self.text = text
        self.wordCount = text.split { $0.isWhitespace || $0.isNewline }.count
        self.anchorData = anchorData
    }
}
