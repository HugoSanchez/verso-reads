//
//  Annotation.swift
//  verso-reads
//

import Foundation
import SwiftData

enum AnnotationKind: String, Codable {
    case highlight
    case noteQuote
    case comment
    case chatPin
}

@Model
final class Annotation {
    @Attribute(.unique) var id: UUID
    var documentID: UUID
    var kindRawValue: String
    var anchorData: Data
    var quote: String?
    var body: String?
    var chatMessageID: UUID?
    var chatPromptID: UUID?
    var chatPromptSnapshot: String?
    var colorRawValue: String?
    var createdAt: Date
    var updatedAt: Date

    var kind: AnnotationKind {
        get { AnnotationKind(rawValue: kindRawValue) ?? .highlight }
        set { kindRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        documentID: UUID,
        kind: AnnotationKind,
        anchorData: Data,
        quote: String? = nil,
        body: String? = nil,
        chatMessageID: UUID? = nil,
        chatPromptID: UUID? = nil,
        chatPromptSnapshot: String? = nil,
        colorRawValue: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.documentID = documentID
        self.kindRawValue = kind.rawValue
        self.anchorData = anchorData
        self.quote = quote
        self.body = body
        self.chatMessageID = chatMessageID
        self.chatPromptID = chatPromptID
        self.chatPromptSnapshot = chatPromptSnapshot
        self.colorRawValue = colorRawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}
