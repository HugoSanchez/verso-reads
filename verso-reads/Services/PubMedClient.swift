//
//  PubMedClient.swift
//  verso-reads
//

import Foundation
import os

private let log = Logger(subsystem: "com.verso.agent", category: "pubmed")

struct PubMedPaper {
    let pmid: String
    let title: String
    let authors: [String]
    let abstract: String
    let published: String
    let journal: String
    let pdfURL: String?
}

struct PubMedClient {
    private let searchURL = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
    private let fetchURL = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
    private let maxAbstractLength = 300

    func search(query: String, maxResults: Int = 5) async throws -> [PubMedPaper] {
        let clampedMax = min(max(maxResults, 1), 10)

        // Step 1: Search for PMIDs
        var searchComponents = URLComponents(string: searchURL)!
        searchComponents.queryItems = [
            URLQueryItem(name: "db", value: "pubmed"),
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "retmax", value: "\(clampedMax)"),
            URLQueryItem(name: "sort", value: "relevance"),
            URLQueryItem(name: "retmode", value: "json")
        ]

        guard let searchURL = searchComponents.url else {
            throw URLError(.badURL)
        }

        log.debug("Searching PubMed: \(query) (max: \(clampedMax))")

        let (searchData, searchResponse) = try await URLSession.shared.data(from: searchURL)
        if let httpResponse = searchResponse as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }

        let searchResult = try JSONDecoder().decode(PubMedSearchResult.self, from: searchData)
        let pmids = searchResult.esearchresult?.idlist ?? []

        guard pmids.isEmpty == false else {
            return []
        }

        // Step 2: Fetch details for each PMID
        var fetchComponents = URLComponents(string: self.fetchURL)!
        fetchComponents.queryItems = [
            URLQueryItem(name: "db", value: "pubmed"),
            URLQueryItem(name: "id", value: pmids.joined(separator: ",")),
            URLQueryItem(name: "retmode", value: "xml")
        ]

        guard let detailURL = fetchComponents.url else {
            throw URLError(.badURL)
        }

        let (detailData, detailResponse) = try await URLSession.shared.data(from: detailURL)
        if let httpResponse = detailResponse as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }

        let parser = PubMedXMLParser(data: detailData, maxAbstractLength: maxAbstractLength)
        let papers = parser.parse()
        log.debug("PubMed returned \(papers.count) result(s)")
        return papers
    }
}

// MARK: - Search Response

private struct PubMedSearchResult: Codable {
    let esearchresult: PubMedSearchData?
}

private struct PubMedSearchData: Codable {
    let idlist: [String]?
}

// MARK: - XML Parser for efetch results

private final class PubMedXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private let maxAbstractLength: Int

    private var papers: [PubMedPaper] = []
    private var currentElement = ""
    private var currentText = ""
    private var elementStack: [String] = []

    // Per-article state
    private var pmid = ""
    private var title = ""
    private var authors: [String] = []
    private var abstract = ""
    private var year = ""
    private var journal = ""
    private var currentAuthorLastName = ""
    private var currentAuthorForeName = ""
    private var inArticle = false

    init(data: Data, maxAbstractLength: Int) {
        self.data = data
        self.maxAbstractLength = maxAbstractLength
    }

    func parse() -> [PubMedPaper] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return papers
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        elementStack.append(elementName)
        currentElement = elementName
        currentText = ""

        if elementName == "PubmedArticle" {
            inArticle = true
            pmid = ""
            title = ""
            authors = []
            abstract = ""
            year = ""
            journal = ""
        } else if elementName == "Author" {
            currentAuthorLastName = ""
            currentAuthorForeName = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inArticle {
            switch elementName {
            case "PMID":
                // Only capture the first PMID (the article's own)
                if pmid.isEmpty && elementStack.contains("MedlineCitation") {
                    pmid = trimmed
                }
            case "ArticleTitle":
                title = trimmed
            case "AbstractText":
                if abstract.isEmpty {
                    let cleaned = trimmed.replacingOccurrences(of: "\n", with: " ")
                    abstract = String(cleaned.prefix(maxAbstractLength))
                    if cleaned.count > maxAbstractLength {
                        abstract += "..."
                    }
                }
            case "Year":
                if year.isEmpty && elementStack.contains("PubDate") {
                    year = trimmed
                }
            case "Title":
                // Journal title (inside <Journal><Title>)
                if elementStack.contains("Journal") {
                    journal = trimmed
                }
            case "LastName":
                if elementStack.contains("Author") {
                    currentAuthorLastName = trimmed
                }
            case "ForeName":
                if elementStack.contains("Author") {
                    currentAuthorForeName = trimmed
                }
            case "Author":
                let name = [currentAuthorForeName, currentAuthorLastName]
                    .filter { $0.isEmpty == false }
                    .joined(separator: " ")
                if name.isEmpty == false {
                    authors.append(name)
                }
            case "PubmedArticle":
                papers.append(PubMedPaper(
                    pmid: pmid,
                    title: title,
                    authors: authors,
                    abstract: abstract,
                    published: year,
                    journal: journal,
                    pdfURL: nil
                ))
                inArticle = false
            default:
                break
            }
        }

        elementStack.removeLast()
        currentElement = elementStack.last ?? ""
        currentText = ""
    }
}
