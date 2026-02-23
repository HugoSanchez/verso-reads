//
//  RAGTextExtractor.swift
//  verso-reads
//

import Foundation
import PDFKit

struct PDFPageText {
    let pageIndex: Int
    let text: String
}

enum RAGTextExtractor {
    enum ExtractionError: Error {
        case invalidDocument
    }

    @MainActor static func extractPages(from url: URL) throws -> [PDFPageText] {
        guard let document = PDFDocument(url: url) else {
            throw ExtractionError.invalidDocument
        }

        var pages: [PDFPageText] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let rawText = page.string ?? ""
            let text = normalize(rawText)
            if text.isEmpty == false {
                pages.append(PDFPageText(pageIndex: index + 1, text: text))
            }
        }

        return pages
    }

    private static func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }
        return trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
