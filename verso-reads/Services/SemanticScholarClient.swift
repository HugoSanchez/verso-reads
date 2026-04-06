//
//  SemanticScholarClient.swift
//  verso-reads
//

import Foundation
import os

private let log = Logger(subsystem: "com.verso.agent", category: "s2")

struct S2Paper {
    let paperId: String
    let title: String
    let authors: [String]
    let abstract: String
    let year: Int?
    let citationCount: Int?
    let venue: String?
    let pdfURL: String?
}

struct SemanticScholarClient {
    private let baseURL = "https://api.semanticscholar.org/graph/v1/paper/search"
    private let maxAbstractLength = 300

    private let maxRetries = 2

    func search(query: String, maxResults: Int = 5) async throws -> [S2Paper] {
        let clampedMax = min(max(maxResults, 1), 10)
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: "\(clampedMax)"),
            URLQueryItem(name: "fields", value: "title,authors,abstract,year,citationCount,venue,openAccessPdf")
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        log.debug("Searching Semantic Scholar: \(query) (max: \(clampedMax))")

        var lastStatusCode = 0
        for attempt in 0...maxRetries {
            if attempt > 0 {
                let delay = UInt64(attempt) * 2_000_000_000 // 2s, 4s
                try await Task.sleep(nanoseconds: delay)
                log.debug("Retrying Semantic Scholar (attempt \(attempt + 1))")
            }

            let (data, response) = try await URLSession.shared.data(from: url)

            if let httpResponse = response as? HTTPURLResponse {
                lastStatusCode = httpResponse.statusCode
                if httpResponse.statusCode == 429 {
                    continue // retry on rate limit
                }
                if httpResponse.statusCode != 200 {
                    throw S2Error.httpError(httpResponse.statusCode)
                }
            }

            let decoded = try JSONDecoder().decode(S2SearchResponse.self, from: data)
            let papers = (decoded.data ?? []).map { entry in
                var abstract = (entry.abstract ?? "").replacingOccurrences(of: "\n", with: " ")
                if abstract.count > maxAbstractLength {
                    abstract = String(abstract.prefix(maxAbstractLength)) + "..."
                }

                return S2Paper(
                    paperId: entry.paperId,
                    title: entry.title ?? "Untitled",
                    authors: (entry.authors ?? []).compactMap { $0.name },
                    abstract: abstract,
                    year: entry.year,
                    citationCount: entry.citationCount,
                    venue: entry.venue,
                    pdfURL: entry.openAccessPdf?.url
                )
            }

            log.debug("Semantic Scholar returned \(papers.count) result(s)")
            return papers
        }

        throw S2Error.rateLimited
    }

    enum S2Error: LocalizedError, Equatable {
        case rateLimited
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .rateLimited:
                return "Semantic Scholar is rate-limiting requests right now. Try again in a few seconds."
            case .httpError(let code):
                return "Semantic Scholar returned HTTP \(code)."
            }
        }
    }
}

// MARK: - Codable Response Types

private struct S2SearchResponse: Codable {
    let total: Int?
    let data: [S2PaperEntry]?
}

private struct S2PaperEntry: Codable {
    let paperId: String
    let title: String?
    let authors: [S2Author]?
    let abstract: String?
    let year: Int?
    let citationCount: Int?
    let venue: String?
    let openAccessPdf: S2OpenAccessPdf?
}

private struct S2Author: Codable {
    let name: String?
}

private struct S2OpenAccessPdf: Codable {
    let url: String?
}
