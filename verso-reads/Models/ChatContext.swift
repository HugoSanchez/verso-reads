//
//  ChatContext.swift
//  verso-reads
//

import Foundation

struct ChatContext: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let wordCount: Int

    init(text: String) {
        self.text = text
        self.wordCount = text.split { $0.isWhitespace || $0.isNewline }.count
    }
}
