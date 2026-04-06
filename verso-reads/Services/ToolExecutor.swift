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
    let turnID: UUID

    private let maxResultLength = 4000

    init(documentID: UUID, apiKey: String, modelContext: ModelContext, document: LibraryDocument? = nil, currentPageProvider: @escaping () -> Int? = { nil }, readerSession: ReaderSession? = nil, turnID: UUID = UUID()) {
        self.documentID = documentID
        self.apiKey = apiKey
        self.modelContext = modelContext
        self.document = document
        self.currentPageProvider = currentPageProvider
        self.readerSession = readerSession
        self.turnID = turnID
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
            case "create_highlight":
                result = try executeCreateHighlight(arguments: arguments)
            case "delete_highlight":
                result = try executeDeleteHighlight(arguments: arguments)
            case "update_highlight":
                result = try executeUpdateHighlight(arguments: arguments)
            case "undo_last_action":
                result = try executeUndoLastAction()
            case "get_library":
                result = try executeGetLibrary()
            case "get_collections":
                result = try executeGetCollections()
            case "get_chat_history":
                result = try executeGetChatHistory(arguments: arguments)
            case "search_all_documents":
                result = try await executeSearchAllDocuments(arguments: arguments)
            case "search_arxiv":
                result = try await executeSearchArxiv(arguments: arguments)
            case "search_semantic_scholar":
                result = try await executeSearchSemanticScholar(arguments: arguments)
            case "search_pubmed":
                result = try await executeSearchPubmed(arguments: arguments)
            case "download_paper":
                result = try await executeDownloadPaper(arguments: arguments)
            case "add_to_collection":
                result = try executeAddToCollection(arguments: arguments)
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
            "id": document.id.uuidString,
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

    private func executeCreateHighlight(arguments: String) throws -> String {
        guard let args = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              let quote = args["quote"] as? String,
              let pageNum = args["page"] as? Int else {
            return "{\"error\": \"Missing required parameters: quote and page\"}"
        }

        guard let document else {
            return "{\"error\": \"No document is currently open.\"}"
        }

        guard let fileURL = try? LibraryStore.fileURL(for: document),
              let pdf = PDFDocument(url: fileURL) else {
            return "{\"error\": \"Could not open PDF file.\"}"
        }

        let pageIndex = pageNum - 1
        guard let matchResult = PDFTextMatcher.match(quote: quote, on: pageIndex, in: pdf) else {
            return "{\"error\": \"Could not find the text \\\"\(String(quote.prefix(80)))\\\" in the document. Try using get_page_text to read the exact text from the page first, then use that exact text as the quote.\"}"
        }

        let colorString = (args["color"] as? String) ?? "yellow"
        let anchorData = try JSONEncoder().encode(matchResult.anchor)
        let actualPage = matchResult.pageIndex + 1

        let annotation = Annotation(
            documentID: documentID,
            kind: .highlight,
            anchorData: anchorData,
            quote: matchResult.matchedText,
            colorRawValue: colorString,
            agentTurnID: turnID
        )

        modelContext.insert(annotation)
        try modelContext.save()

        log.debug("Created highlight \(annotation.id) on page \(actualPage) color=\(colorString)")
        return "{\"success\": true, \"id\": \"\(annotation.id.uuidString)\", \"page\": \(actualPage), \"color\": \"\(colorString)\"}"
    }

    private func executeDeleteHighlight(arguments: String) throws -> String {
        guard let args = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              let idString = args["id"] as? String,
              let highlightID = UUID(uuidString: idString) else {
            return "{\"error\": \"Missing or invalid required parameter: id (must be a valid UUID)\"}"
        }

        let descriptor = FetchDescriptor<Annotation>()
        let allAnnotations = try modelContext.fetch(descriptor)
        guard let annotation = allAnnotations.first(where: {
            $0.id == highlightID && $0.documentID == documentID && $0.kind == .highlight
        }) else {
            return "{\"error\": \"Highlight with ID \(idString) not found in this document.\"}"
        }

        modelContext.delete(annotation)
        try modelContext.save()

        log.debug("Deleted highlight \(idString)")
        return "{\"success\": true, \"deleted\": \"\(idString)\"}"
    }

    private func executeUpdateHighlight(arguments: String) throws -> String {
        guard let args = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              let idString = args["id"] as? String,
              let highlightID = UUID(uuidString: idString),
              let color = args["color"] as? String else {
            return "{\"error\": \"Missing required parameters: id and color\"}"
        }

        let descriptor = FetchDescriptor<Annotation>()
        let allAnnotations = try modelContext.fetch(descriptor)
        guard let annotation = allAnnotations.first(where: {
            $0.id == highlightID && $0.documentID == documentID && $0.kind == .highlight
        }) else {
            return "{\"error\": \"Highlight with ID \(idString) not found in this document.\"}"
        }

        annotation.colorRawValue = color
        annotation.updatedAt = Date()
        try modelContext.save()

        log.debug("Updated highlight \(idString) color=\(color)")
        return "{\"success\": true, \"id\": \"\(idString)\", \"color\": \"\(color)\"}"
    }

    private func executeUndoLastAction() throws -> String {
        let descriptor = FetchDescriptor<Annotation>()
        let allAnnotations = try modelContext.fetch(descriptor)
        let turnAnnotations = allAnnotations.filter {
            $0.documentID == documentID && $0.agentTurnID == turnID
        }

        guard turnAnnotations.isEmpty == false else {
            return "{\"error\": \"No actions to undo in this turn.\"}"
        }

        for annotation in turnAnnotations {
            modelContext.delete(annotation)
        }
        try modelContext.save()

        log.debug("Undid \(turnAnnotations.count) action(s) from turn \(self.turnID)")
        return "{\"success\": true, \"undone\": \(turnAnnotations.count)}"
    }

    // MARK: - Cross-Document Tools

    private func executeGetLibrary() throws -> String {
        let descriptor = FetchDescriptor<LibraryDocument>()
        let allDocs = try modelContext.fetch(descriptor)
        let sorted = allDocs.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
        let limited = Array(sorted.prefix(50))

        let items: [[String: Any]] = limited.map { doc in
            var item: [String: Any] = [
                "id": doc.id.uuidString,
                "title": doc.title,
                "filename": doc.originalFilename
            ]
            let formatter = ISO8601DateFormatter()
            item["lastOpenedAt"] = formatter.string(from: doc.lastOpenedAt)
            return item
        }

        let data = try JSONSerialization.data(withJSONObject: items, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func executeGetCollections() throws -> String {
        let collectionDescriptor = FetchDescriptor<DocumentCollection>()
        let collections = try modelContext.fetch(collectionDescriptor)

        let docDescriptor = FetchDescriptor<LibraryDocument>()
        let allDocs = try modelContext.fetch(docDescriptor)
        let docsByID = Dictionary(uniqueKeysWithValues: allDocs.map { ($0.id, $0) })

        let items: [[String: Any]] = collections.map { collection in
            let docs: [[String: String]] = collection.documentIDs.compactMap { docID in
                guard let doc = docsByID[docID] else { return nil }
                return ["id": docID.uuidString, "title": doc.title]
            }
            return [
                "id": collection.id.uuidString,
                "name": collection.name,
                "documents": docs
            ] as [String: Any]
        }

        let data = try JSONSerialization.data(withJSONObject: items, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func executeGetChatHistory(arguments: String) throws -> String {
        let targetID: UUID
        if let args = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
           let idString = args["document_id"] as? String,
           idString.isEmpty == false,
           idString.lowercased() != "current",
           let parsed = UUID(uuidString: idString) {
            targetID = parsed
        } else {
            targetID = documentID
        }

        let descriptor = FetchDescriptor<ChatMessageRecord>()
        let allMessages = try modelContext.fetch(descriptor)
        let filtered = allMessages
            .filter { $0.documentID == targetID }
            .sorted { $0.createdAt < $1.createdAt }
        let limited = Array(filtered.suffix(30))

        guard limited.isEmpty == false else {
            return "No chat history found for this document."
        }

        let formatter = ISO8601DateFormatter()
        let items: [[String: String]] = limited.map { record in
            [
                "role": record.roleRawValue,
                "content": String(record.content.prefix(500)),
                "createdAt": formatter.string(from: record.createdAt)
            ]
        }

        let data = try JSONSerialization.data(withJSONObject: items, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func executeSearchAllDocuments(arguments: String) async throws -> String {
        guard let args = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              let query = args["query"] as? String else {
            return "{\"error\": \"Missing required parameter: query\"}"
        }

        guard let context = try await RAGQueryService.shared.retrieveContextAll(
            query: query,
            apiKey: apiKey
        ) else {
            return "No relevant passages found across your library for: \"\(query)\""
        }

        return context
    }

    // MARK: - External Research Tools

    private func executeSearchArxiv(arguments: String) async throws -> String {
        guard let args = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              let query = args["query"] as? String else {
            return "{\"error\": \"Missing required parameter: query\"}"
        }

        let maxResults = (args["max_results"] as? Int) ?? 5
        let papers = try await ArxivClient().search(query: query, maxResults: maxResults)

        guard papers.isEmpty == false else {
            return "No papers found on arXiv for: \"\(query)\""
        }

        let items: [[String: Any]] = papers.map { paper in
            [
                "arxiv_id": paper.arxivID,
                "title": paper.title,
                "authors": paper.authors,
                "abstract": paper.abstract,
                "published": paper.published,
                "pdf_url": paper.pdfURL
            ] as [String: Any]
        }

        let data = try JSONSerialization.data(withJSONObject: items, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func executeSearchSemanticScholar(arguments: String) async throws -> String {
        guard let args = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              let query = args["query"] as? String else {
            return "{\"error\": \"Missing required parameter: query\"}"
        }

        let maxResults = (args["max_results"] as? Int) ?? 5
        let papers: [S2Paper]
        do {
            papers = try await SemanticScholarClient().search(query: query, maxResults: maxResults)
        } catch let error as SemanticScholarClient.S2Error where error == .rateLimited {
            return "{\"error\": \"Semantic Scholar is temporarily unavailable due to rate limiting. You can try search_arxiv instead, or use the web_search tool as a fallback.\"}"
        }

        guard papers.isEmpty == false else {
            return "No papers found on Semantic Scholar for: \"\(query)\""
        }

        let items: [[String: Any]] = papers.map { paper in
            var item: [String: Any] = [
                "paper_id": paper.paperId,
                "title": paper.title,
                "authors": paper.authors,
                "abstract": paper.abstract
            ]
            if let year = paper.year { item["year"] = year }
            if let citations = paper.citationCount { item["citation_count"] = citations }
            if let venue = paper.venue, venue.isEmpty == false { item["venue"] = venue }
            if let pdfURL = paper.pdfURL { item["pdf_url"] = pdfURL }
            return item
        }

        let data = try JSONSerialization.data(withJSONObject: items, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func executeSearchPubmed(arguments: String) async throws -> String {
        guard let args = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              let query = args["query"] as? String else {
            return "{\"error\": \"Missing required parameter: query\"}"
        }

        let maxResults = (args["max_results"] as? Int) ?? 5
        let papers = try await PubMedClient().search(query: query, maxResults: maxResults)

        guard papers.isEmpty == false else {
            return "No papers found on PubMed for: \"\(query)\""
        }

        let items: [[String: Any]] = papers.map { paper in
            var item: [String: Any] = [
                "pmid": paper.pmid,
                "title": paper.title,
                "authors": paper.authors,
                "abstract": paper.abstract,
                "pubmed_url": "https://pubmed.ncbi.nlm.nih.gov/\(paper.pmid)/"
            ]
            if paper.published.isEmpty == false { item["published"] = paper.published }
            if paper.journal.isEmpty == false { item["journal"] = paper.journal }
            item["downloadable"] = false
            return item
        }

        let data = try JSONSerialization.data(withJSONObject: items, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static let allowedDownloadDomains: Set<String> = [
        "arxiv.org",
        "export.arxiv.org",
        "semanticscholar.org",
        "pdfs.semanticscholar.org",
        "openreview.net",
        "aclanthology.org",
        "proceedings.neurips.cc",
        "proceedings.mlr.press",
        "ncbi.nlm.nih.gov"
    ]

    private static let maxDownloadSize = 50 * 1024 * 1024 // 50MB

    private func executeDownloadPaper(arguments: String) async throws -> String {
        guard let args = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              let urlString = args["url"] as? String,
              let title = args["title"] as? String else {
            return "{\"error\": \"Missing required parameters: url and title\"}"
        }

        guard let url = URL(string: urlString),
              let host = url.host?.lowercased(),
              url.scheme == "https" || url.scheme == "http" else {
            return "{\"error\": \"Invalid URL.\"}"
        }

        // Validate domain
        let isAllowed = Self.allowedDownloadDomains.contains(where: { domain in
            host == domain || host.hasSuffix(".\(domain)")
        })
        guard isAllowed else {
            return "{\"error\": \"Downloads are only allowed from academic sources (arxiv.org, semanticscholar.org, openreview.net, etc). Domain '\(host)' is not allowed.\"}"
        }

        log.debug("Downloading paper: \(title) from \(urlString)")

        // Download
        let (data, response) = try await URLSession.shared.data(from: url)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            return "{\"error\": \"Download failed with HTTP \(httpResponse.statusCode).\"}"
        }

        guard data.count <= Self.maxDownloadSize else {
            return "{\"error\": \"File is too large (\(data.count / 1024 / 1024)MB). Maximum is 50MB.\"}"
        }

        // Write to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let sanitizedTitle = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let tempFile = tempDir.appendingPathComponent("\(sanitizedTitle).pdf")
        try data.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        // Import into library
        let document = try LibraryStore.importDocument(from: tempFile, modelContext: modelContext)

        // Set the title to the paper title instead of the filename
        document.title = title
        try modelContext.save()

        // Handle optional collection
        let collectionName = args["collection_name"] as? String
        if let collectionName, collectionName.isEmpty == false {
            let collectionDescriptor = FetchDescriptor<DocumentCollection>()
            let collections = try modelContext.fetch(collectionDescriptor)
            let collection = collections.first(where: {
                $0.name.lowercased() == collectionName.lowercased()
            }) ?? {
                let newCollection = DocumentCollection(name: collectionName)
                modelContext.insert(newCollection)
                return newCollection
            }()
            collection.addDocument(document.id)
            try modelContext.save()
        }

        // Trigger RAG ingestion in background, passing the API key to avoid Keychain prompts
        let docForIngestion = document
        let fileURL = try LibraryStore.fileURL(for: docForIngestion)
        let ingestionKey = apiKey
        Task.detached {
            await RAGIngestionManager.shared.enqueue(document: docForIngestion, fileURL: fileURL, apiKey: ingestionKey)
        }

        log.debug("Imported paper: \(document.id) - \(title)")

        var result: [String: Any] = [
            "success": true,
            "document_id": document.id.uuidString,
            "title": title
        ]
        if let collectionName, collectionName.isEmpty == false {
            result["added_to_collection"] = collectionName
        }

        let resultData = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        return String(data: resultData, encoding: .utf8) ?? "{}"
    }

    private func executeAddToCollection(arguments: String) throws -> String {
        guard let args = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              let docIDString = args["document_id"] as? String,
              let docID = UUID(uuidString: docIDString),
              let collectionName = args["collection_name"] as? String else {
            return "{\"error\": \"Missing required parameters: document_id and collection_name\"}"
        }

        // Verify document exists
        let docDescriptor = FetchDescriptor<LibraryDocument>()
        let allDocs = try modelContext.fetch(docDescriptor)
        guard allDocs.contains(where: { $0.id == docID }) else {
            return "{\"error\": \"Document with ID \(docIDString) not found.\"}"
        }

        let collectionDescriptor = FetchDescriptor<DocumentCollection>()
        let collections = try modelContext.fetch(collectionDescriptor)
        let collection = collections.first(where: {
            $0.name.lowercased() == collectionName.lowercased()
        }) ?? {
            let newCollection = DocumentCollection(name: collectionName)
            modelContext.insert(newCollection)
            return newCollection
        }()

        collection.addDocument(docID)
        try modelContext.save()

        log.debug("Added \(docIDString) to collection '\(collectionName)'")
        return "{\"success\": true, \"collection_id\": \"\(collection.id.uuidString)\", \"collection_name\": \"\(collection.name)\"}"
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
