//
//  ToolExecutor.swift
//  verso-reads
//

import Foundation
import PDFKit
import SwiftData
import os

private let log = Logger(subsystem: "com.verso.agent", category: "tool")

@MainActor
final class ToolExecutor {
    let documentID: UUID
    let apiKey: String
    let modelContext: ModelContext
    let document: LibraryDocument?
    let currentPageProvider: () -> Int?
    let readerSession: ReaderSession?

    private let maxResultLength = 4000

    init(documentID: UUID, apiKey: String, modelContext: ModelContext, document: LibraryDocument? = nil, currentPageProvider: @escaping () -> Int? = { nil }, readerSession: ReaderSession? = nil) {
        self.documentID = documentID
        self.apiKey = apiKey
        self.modelContext = modelContext
        self.document = document
        self.currentPageProvider = currentPageProvider
        self.readerSession = readerSession
    }

    func execute(name: String, arguments: String) async -> String {
        log.debug("Executing: \(name)(\(arguments))")

        do {
            let result: String
            switch name {
            case "search_document":
                result = try await executeSearchDocument(arguments: arguments)
            case "read_highlights":
                result = try executeReadHighlights()
            case "read_notes":
                result = try executeReadNotes()
            case "get_document_info":
                result = try executeGetDocumentInfo()
            case "get_current_page":
                result = executeGetCurrentPage()
            case "get_page_text":
                result = try executeGetPageText(arguments: arguments)
            case "navigate_to_page":
                result = executeNavigateToPage(arguments: arguments)
            case "create_note":
                result = try executeCreateNote(arguments: arguments)
            case "append_to_note":
                result = try executeAppendToNote(arguments: arguments)
            default:
                result = "{\"error\": \"Unknown tool: \(name)\"}"
            }

            log.debug("\(name) returned \(result.count) chars")
            return String(result.prefix(maxResultLength))
        } catch {
            log.error("ERROR \(name): \(error.localizedDescription)")
            return "{\"error\": \"\(error.localizedDescription)\"}"
        }
    }

    // MARK: - Tool Implementations

    private func executeSearchDocument(arguments: String) async throws -> String {
        guard let args = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              let query = args["query"] as? String else {
            return "{\"error\": \"Missing required parameter: query\"}"
        }

        guard let context = try await RAGQueryService.shared.retrieveContext(
            documentID: documentID,
            query: query,
            apiKey: apiKey
        ) else {
            return "No relevant passages found for query: \"\(query)\""
        }

        return context
    }

    private func executeReadHighlights() throws -> String {
        let descriptor = FetchDescriptor<Annotation>()
        let allAnnotations = try modelContext.fetch(descriptor)
        let highlights = allAnnotations.filter {
            $0.documentID == documentID && $0.kind == .highlight
        }

        guard highlights.isEmpty == false else {
            return "No highlights found for this document."
        }

        let items: [[String: Any]] = highlights.prefix(50).map { annotation in
            var item: [String: Any] = [
                "id": annotation.id.uuidString
            ]
            if let quote = annotation.quote {
                item["quote"] = String(quote.prefix(200))
            }
            if let color = annotation.colorRawValue {
                item["color"] = color
            }
            if let anchor = try? JSONDecoder().decode(PDFHighlightAnchor.self, from: annotation.anchorData),
               let firstFragment = anchor.fragments.first {
                item["page"] = firstFragment.pageIndex + 1
            }
            return item
        }

        let data = try JSONSerialization.data(withJSONObject: items, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func executeReadNotes() throws -> String {
        let descriptor = FetchDescriptor<DocumentNote>()
        let allNotes = try modelContext.fetch(descriptor)
        guard let note = allNotes.first(where: { $0.documentID == documentID }) else {
            return "No notes found for this document."
        }

        let content = note.content
        guard content.isEmpty == false else {
            return "The notepad is empty."
        }

        return extractPlainText(fromTipTapJSON: content)
    }

    private func executeGetDocumentInfo() throws -> String {
        guard let document else {
            return "{\"error\": \"No document is currently open.\"}"
        }

        var info: [String: Any] = [
            "title": document.title,
            "filename": document.originalFilename,
            "fileType": document.contentTypeIdentifier
        ]

        if let fileURL = try? LibraryStore.fileURL(for: document),
           let pdf = PDFDocument(url: fileURL) {
            info["pageCount"] = pdf.pageCount
            if let attrs = pdf.documentAttributes {
                if let author = attrs[PDFDocumentAttribute.authorAttribute] as? String {
                    info["author"] = author
                }
                if let subject = attrs[PDFDocumentAttribute.subjectAttribute] as? String {
                    info["subject"] = subject
                }
            }
        }

        let data = try JSONSerialization.data(withJSONObject: info, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func executeGetCurrentPage() -> String {
        if let page = currentPageProvider() {
            return "{\"currentPage\": \(page)}"
        }
        return "{\"error\": \"Could not determine current page.\"}"
    }

    private func executeGetPageText(arguments: String) throws -> String {
        guard let args = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              let pageNum = args["page"] as? Int else {
            return "{\"error\": \"Missing required parameter: page\"}"
        }

        guard let document else {
            return "{\"error\": \"No document is currently open.\"}"
        }

        guard let fileURL = try? LibraryStore.fileURL(for: document),
              let pdf = PDFDocument(url: fileURL) else {
            return "{\"error\": \"Could not open PDF file.\"}"
        }

        let pageIndex = pageNum - 1
        guard pageIndex >= 0, pageIndex < pdf.pageCount,
              let page = pdf.page(at: pageIndex) else {
            return "{\"error\": \"Page \(pageNum) is out of range. Document has \(pdf.pageCount) pages.\"}"
        }

        guard let text = page.string, text.isEmpty == false else {
            return "Page \(pageNum) contains no extractable text."
        }

        return text
    }

    private func executeNavigateToPage(arguments: String) -> String {
        guard let args = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              let pageNum = args["page"] as? Int else {
            return "{\"error\": \"Missing required parameter: page\"}"
        }

        guard let readerSession else {
            return "{\"error\": \"Navigation is not available.\"}"
        }

        readerSession.pendingPageNavigation = pageNum
        return "{\"success\": true, \"navigatedTo\": \(pageNum)}"
    }

    private func executeCreateNote(arguments: String) throws -> String {
        guard let args = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              let text = args["text"] as? String else {
            return "{\"error\": \"Missing required parameter: text\"}"
        }

        let descriptor = FetchDescriptor<DocumentNote>()
        let allNotes = try modelContext.fetch(descriptor)

        if allNotes.contains(where: { $0.documentID == documentID }) {
            return "{\"error\": \"A note already exists for this document. Use append_to_note to add content to it.\"}"
        }

        guard let readerSession else {
            return "{\"error\": \"Notes are not available.\"}"
        }

        // Use the same TipTap JS path — appendText handles empty notes too
        readerSession.pendingNoteAppend = text
        return "{\"success\": true, \"action\": \"created\"}"
    }

    private func executeAppendToNote(arguments: String) throws -> String {
        guard let args = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              let text = args["text"] as? String else {
            return "{\"error\": \"Missing required parameter: text\"}"
        }

        guard let readerSession else {
            return "{\"error\": \"Notes are not available.\"}"
        }

        readerSession.pendingNoteAppend = text
        return "{\"success\": true, \"action\": \"appended\"}"
    }

    // MARK: - Helpers

    private func extractPlainText(fromTipTapJSON json: String) -> String {
        guard let data = json.data(using: .utf8),
              let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentNodes = doc["content"] as? [[String: Any]] else {
            return json
        }

        var lines: [String] = []
        for node in contentNodes {
            let text = extractTextFromNode(node)
            if text.isEmpty == false {
                lines.append(text)
            }
        }
        return lines.joined(separator: "\n")
    }

    private func extractTextFromNode(_ node: [String: Any]) -> String {
        var result = ""

        if let text = node["text"] as? String {
            result += text
        }

        if let content = node["content"] as? [[String: Any]] {
            for child in content {
                result += extractTextFromNode(child)
            }
        }

        return result
    }

    private func buildTipTapDocument(from text: String) -> String {
        let paragraphs = text.components(separatedBy: "\n").filter { $0.isEmpty == false }
        let nodes: [[String: Any]] = paragraphs.map { line in
            [
                "type": "paragraph",
                "content": [["type": "text", "text": line]]
            ]
        }
        let doc: [String: Any] = ["type": "doc", "content": nodes.isEmpty ? [["type": "paragraph"]] : nodes]
        guard let data = try? JSONSerialization.data(withJSONObject: doc, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"type\":\"doc\",\"content\":[{\"type\":\"paragraph\"}]}"
        }
        return json
    }

    private func appendToTipTapDocument(_ existingJSON: String, text: String) -> String {
        guard let data = existingJSON.data(using: .utf8),
              var doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var content = doc["content"] as? [[String: Any]] else {
            return buildTipTapDocument(from: text)
        }

        // Add an empty paragraph as separator
        content.append(["type": "paragraph"])

        // Add new paragraphs
        let paragraphs = text.components(separatedBy: "\n").filter { $0.isEmpty == false }
        for line in paragraphs {
            content.append([
                "type": "paragraph",
                "content": [["type": "text", "text": line]]
            ])
        }

        doc["content"] = content
        guard let resultData = try? JSONSerialization.data(withJSONObject: doc, options: []),
              let json = String(data: resultData, encoding: .utf8) else {
            return existingJSON
        }
        return json
    }
}
