//
//  LibraryDocument.swift
//  verso-reads
//
//  Stores metadata for imported reading files.
//

import Foundation
import SwiftData

@Model
final class LibraryDocument {
    @Attribute(.unique) var id: UUID
    var title: String
    var originalFilename: String
    var contentTypeIdentifier: String
    var relativePath: String
    var createdAt: Date
    var lastOpenedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        originalFilename: String,
        contentTypeIdentifier: String,
        relativePath: String,
        createdAt: Date = Date(),
        lastOpenedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.originalFilename = originalFilename
        self.contentTypeIdentifier = contentTypeIdentifier
        self.relativePath = relativePath
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt ?? createdAt
    }
}

