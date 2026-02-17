//
//  LibraryStore.swift
//  verso-reads
//

import Foundation
import SwiftData
import UniformTypeIdentifiers

enum LibraryStore {
    enum LibraryStoreError: Swift.Error {
        case missingApplicationSupportDirectory
    }

    static func importDocument(from sourceURL: URL, modelContext: ModelContext) throws -> LibraryDocument {
        let docID = UUID()
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let libraryRoot = try libraryRootURL()
        let documentFolder = libraryRoot.appendingPathComponent(docID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: documentFolder, withIntermediateDirectories: true)

        let fileExtension = sourceURL.pathExtension.isEmpty ? "pdf" : sourceURL.pathExtension
        let destinationURL = documentFolder
            .appendingPathComponent("document")
            .appendingPathExtension(fileExtension)

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        let title = sourceURL.deletingPathExtension().lastPathComponent
        let contentTypeIdentifier = UTType(filenameExtension: fileExtension)?.identifier ?? UTType.data.identifier
        let relativePath = docID.uuidString + "/" + destinationURL.lastPathComponent

        let document = LibraryDocument(
            id: docID,
            title: title,
            originalFilename: sourceURL.lastPathComponent,
            contentTypeIdentifier: contentTypeIdentifier,
            relativePath: relativePath,
            createdAt: Date()
        )
        document.lastOpenedAt = Date()

        modelContext.insert(document)
        try modelContext.save()

        return document
    }

    static func fileURL(for document: LibraryDocument) throws -> URL {
        try libraryRootURL().appendingPathComponent(document.relativePath)
    }

    static func deleteDocument(_ document: LibraryDocument, modelContext: ModelContext) throws {
        let url = try fileURL(for: document)
        let folderURL = url.deletingLastPathComponent()

        if FileManager.default.fileExists(atPath: folderURL.path) {
            try FileManager.default.removeItem(at: folderURL)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let docID = document.id
        let annotationPredicate = #Predicate<Annotation> { annotation in
            annotation.documentID == docID
        }
        let annotationDescriptor = FetchDescriptor<Annotation>(predicate: annotationPredicate)
        let annotations = try modelContext.fetch(annotationDescriptor)
        for annotation in annotations {
            modelContext.delete(annotation)
        }

        modelContext.delete(document)
        try modelContext.save()
    }

    private static func libraryRootURL() throws -> URL {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw LibraryStoreError.missingApplicationSupportDirectory
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "verso-reads"
        let root = appSupportURL
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
