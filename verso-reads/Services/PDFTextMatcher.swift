//
//  PDFTextMatcher.swift
//  verso-reads
//

import Foundation
import PDFKit
import os

private let log = Logger(subsystem: "com.verso.agent", category: "textmatcher")

/// Matches a text quote to a PDFSelection, handling the fuzzy reality of PDF text extraction.
/// Returns a PDFHighlightAnchor ready for storage in an Annotation.
enum PDFTextMatcher {

    struct MatchResult {
        let anchor: PDFHighlightAnchor
        let matchedText: String
        let pageIndex: Int
    }

    /// Find a text quote on a specific page and return a highlight anchor.
    /// Tries exact match first, then progressively looser strategies.
    static func match(quote: String, on pageIndex: Int, in pdf: PDFDocument) -> MatchResult? {
        log.debug("Matching quote (\(quote.count) chars) on page \(pageIndex + 1): \"\(quote.prefix(60))...\"")

        // Strategy 1: Search on the target page first
        if pageIndex >= 0, pageIndex < pdf.pageCount,
           let page = pdf.page(at: pageIndex),
           let result = findOnPage(quote: quote, page: page, pageIndex: pageIndex) {
            log.debug("Match on target page \(pageIndex + 1)")
            return result
        }

        // Strategy 2: Search nearby pages (model is often off by 1-2)
        let nearbyRange = max(0, pageIndex - 2)...min(pdf.pageCount - 1, pageIndex + 2)
        for i in nearbyRange where i != pageIndex {
            guard let page = pdf.page(at: i) else { continue }
            if let result = findOnPage(quote: quote, page: page, pageIndex: i) {
                log.debug("Match on nearby page \(i + 1) (requested \(pageIndex + 1))")
                return result
            }
        }

        // Strategy 3: Search all remaining pages
        for i in 0..<pdf.pageCount where !nearbyRange.contains(i) {
            guard let page = pdf.page(at: i) else { continue }
            if let result = findOnPage(quote: quote, page: page, pageIndex: i) {
                log.debug("Match on page \(i + 1) (requested \(pageIndex + 1))")
                return result
            }
        }

        log.warning("No match found for: \"\(quote.prefix(80))...\"")
        return nil
    }

    // MARK: - Private

    /// Search for text on a single page using the page's own text string.
    /// This is page-local — it won't accidentally match text on other pages.
    private static func findOnPage(quote: String, page: PDFPage, pageIndex: Int) -> MatchResult? {
        guard let pageText = page.string, pageText.isEmpty == false else { return nil }
        let nsPageText = pageText as NSString

        // Try 1: Case-insensitive search on the page's own text
        var range = nsPageText.range(of: quote, options: [.caseInsensitive])

        // Try 2: Normalized whitespace
        if range.location == NSNotFound {
            let normalizedQuote = normalizeWhitespace(quote)
            let normalizedPage = normalizeWhitespace(pageText)
            let nsNormalized = normalizedPage as NSString
            let normRange = nsNormalized.range(of: normalizedQuote, options: [.caseInsensitive])
            if normRange.location != NSNotFound {
                // Map back to original text range approximately
                range = nsPageText.range(of: normalizedQuote, options: [.caseInsensitive])
                if range.location == NSNotFound {
                    // Use PDFDocument.findString as fallback for normalized matches
                    return findWithDocumentSearch(quote: normalizedQuote, page: page, pageIndex: pageIndex)
                }
            }
        }

        // Try 3: Trimmed substring (handles leading/trailing LLM artifacts)
        if range.location == NSNotFound, quote.count > 40 {
            let trimmed = trimmedSubstring(of: quote, keepRatio: 0.7)
            range = nsPageText.range(of: trimmed, options: [.caseInsensitive])
        }

        guard range.location != NSNotFound else { return nil }

        // Convert NSRange on page text → PDFSelection
        guard let selection = page.selection(for: range) else {
            log.debug("Found text in string but selection(for:) returned nil on page \(pageIndex + 1)")
            return nil
        }

        return buildAnchor(from: selection, on: page, pageIndex: pageIndex)
    }

    /// Fallback: use PDFDocument.findString but strictly filter to the target page.
    private static func findWithDocumentSearch(quote: String, page: PDFPage, pageIndex: Int) -> MatchResult? {
        guard let document = page.document else { return nil }
        let selections = document.findString(quote, withOptions: [.caseInsensitive])

        // Only accept selections whose first page is our target page
        for selection in selections {
            guard let firstPage = selection.pages.first, firstPage == page else { continue }
            return buildAnchor(from: selection, on: page, pageIndex: pageIndex)
        }
        return nil
    }

    /// Convert a PDFSelection to a PDFHighlightAnchor with normalized coordinates.
    private static func buildAnchor(from selection: PDFSelection, on page: PDFPage, pageIndex: Int) -> MatchResult? {
        let lineSelections = selection.selectionsByLine()
        let selections = lineSelections.isEmpty ? [selection] : lineSelections
        let pageBounds = page.bounds(for: .mediaBox)

        var rects: [NormalizedRect] = []
        for lineSelection in selections {
            let bounds = lineSelection.bounds(for: page)
            guard bounds.isEmpty == false, bounds.isNull == false else { continue }

            let x = (bounds.minX - pageBounds.minX) / max(1, pageBounds.width)
            let y = (bounds.minY - pageBounds.minY) / max(1, pageBounds.height)
            let w = bounds.width / max(1, pageBounds.width)
            let h = bounds.height / max(1, pageBounds.height)
            rects.append(NormalizedRect(x: Double(x), y: Double(y), w: Double(w), h: Double(h)))
        }

        guard rects.isEmpty == false else { return nil }

        let fragment = PDFHighlightFragment(pageIndex: pageIndex, rects: rects)
        let anchor = PDFHighlightAnchor(fragments: [fragment])
        let matchedText = selection.string ?? ""

        return MatchResult(anchor: anchor, matchedText: matchedText, pageIndex: pageIndex)
    }

    /// Collapse all whitespace runs (spaces, newlines, tabs) to a single space.
    private static func normalizeWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }

    /// Take the middle ~keepRatio of the string, trimming from both ends.
    private static func trimmedSubstring(of text: String, keepRatio: Double) -> String {
        let trimCount = Int(Double(text.count) * (1.0 - keepRatio) / 2.0)
        let start = text.index(text.startIndex, offsetBy: trimCount)
        let end = text.index(text.endIndex, offsetBy: -trimCount)
        return String(text[start..<end])
    }
}
