//
//  ToolExecutor.swift
//  verso-reads
//

import Foundation
import SwiftData
import os

private let log = Logger(subsystem: "com.verso.agent", category: "tool")

@MainActor
final class ToolExecutor {
    let documentID: UUID
    let apiKey: String
    let modelContext: ModelContext

    private let maxResultLength = 4000

    init(documentID: UUID, apiKey: String, modelContext: ModelContext) {
        self.documentID = documentID
        self.apiKey = apiKey
        self.modelContext = modelContext
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
}
