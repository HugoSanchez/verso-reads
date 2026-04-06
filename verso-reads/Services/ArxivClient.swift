//
//  ArxivClient.swift
//  verso-reads
//

import Foundation
import os

private let log = Logger(subsystem: "com.verso.agent", category: "arxiv")

struct ArxivPaper {
    let arxivID: String
    let title: String
    let authors: [String]
    let abstract: String
    let published: String
    let pdfURL: String
}

struct ArxivClient {
    private let baseURL = "https://export.arxiv.org/api/query"
    private let maxAbstractLength = 300

    func search(query: String, maxResults: Int = 5) async throws -> [ArxivPaper] {
        let clampedMax = min(max(maxResults, 1), 10)
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "search_query", value: "all:\(query)"),
            URLQueryItem(name: "max_results", value: "\(clampedMax)"),
            URLQueryItem(name: "sortBy", value: "relevance"),
            URLQueryItem(name: "sortOrder", value: "descending")
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        log.debug("Searching arXiv: \(query) (max: \(clampedMax))")

        let (data, response) = try await URLSession.shared.data(from: url)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }

        let parser = ArxivXMLParser(data: data, maxAbstractLength: maxAbstractLength)
        let papers = parser.parse()
        log.debug("arXiv returned \(papers.count) result(s)")
        return papers
    }
}

// MARK: - XML Parser

private final class ArxivXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private let maxAbstractLength: Int

    private var papers: [ArxivPaper] = []
    private var currentElement = ""
    private var currentText = ""

    // Per-entry state
    private var entryID = ""
    private var entryTitle = ""
    private var entryAuthors: [String] = []
    private var entryAbstract = ""
    private var entryPublished = ""
    private var entryPDFURL = ""
    private var inEntry = false
    private var inAuthor = false

    init(data: Data, maxAbstractLength: Int) {
        self.data = data
        self.maxAbstractLength = maxAbstractLength
    }

    func parse() -> [ArxivPaper] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return papers
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        if elementName == "entry" {
            inEntry = true
            entryID = ""
            entryTitle = ""
            entryAuthors = []
            entryAbstract = ""
            entryPublished = ""
            entryPDFURL = ""
        } else if elementName == "author" {
            inAuthor = true
        } else if elementName == "link" && inEntry {
            if attributeDict["title"] == "pdf",
               let href = attributeDict["href"] {
                entryPDFURL = href
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inEntry {
            switch elementName {
            case "id":
                entryID = trimmed
            case "title":
                if !inAuthor {
                    entryTitle = trimmed.replacingOccurrences(of: "\n", with: " ")
                }
            case "summary":
                let cleaned = trimmed.replacingOccurrences(of: "\n", with: " ")
                entryAbstract = String(cleaned.prefix(maxAbstractLength))
                if cleaned.count > maxAbstractLength {
                    entryAbstract += "..."
                }
            case "published":
                entryPublished = String(trimmed.prefix(10)) // YYYY-MM-DD
            case "name":
                if inAuthor {
                    entryAuthors.append(trimmed)
                }
            case "author":
                inAuthor = false
            case "entry":
                let arxivID = entryID
                    .replacingOccurrences(of: "http://arxiv.org/abs/", with: "")
                    .replacingOccurrences(of: "https://arxiv.org/abs/", with: "")

                papers.append(ArxivPaper(
                    arxivID: arxivID,
                    title: entryTitle,
                    authors: entryAuthors,
                    abstract: entryAbstract,
                    published: entryPublished,
                    pdfURL: entryPDFURL.isEmpty ? "https://arxiv.org/pdf/\(arxivID)" : entryPDFURL
                ))
                inEntry = false
            default:
                break
            }
        }

        currentElement = ""
        currentText = ""
    }
}
