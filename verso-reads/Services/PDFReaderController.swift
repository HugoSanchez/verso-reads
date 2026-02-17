//
//  PDFReaderController.swift
//  verso-reads
//

import Foundation
import Combine
import PDFKit

@MainActor
final class PDFReaderController: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    weak var pdfView: PDFView?

    func attach(pdfView: PDFView) {
        self.pdfView = pdfView
    }

    func clearSelection() {
        pdfView?.clearSelection()
    }

    func makeHighlightAnchorFromSelection() -> (anchor: PDFHighlightAnchor, quote: String)? {
        guard let pdfView, let selection = pdfView.currentSelection, let document = pdfView.document else { return nil }

        let quote = selection.string ?? ""
        let lineSelections = selection.selectionsByLine()
        let selections = lineSelections.isEmpty ? [selection] : lineSelections

        var rectsByPageIndex: [Int: [CGRect]] = [:]
        for lineSelection in selections {
            for page in lineSelection.pages {
                let pageIndex = document.index(for: page)
                guard pageIndex != NSNotFound else { continue }

                let bounds = lineSelection.bounds(for: page)
                guard bounds.isEmpty == false, bounds.isNull == false else { continue }
                rectsByPageIndex[pageIndex, default: []].append(bounds)
            }
        }

        let fragments: [PDFHighlightFragment] = rectsByPageIndex
            .keys
            .sorted()
            .compactMap { pageIndex in
                guard let page = document.page(at: pageIndex) else { return nil }
                guard let rects = rectsByPageIndex[pageIndex], rects.isEmpty == false else { return nil }
                let pageBounds = page.bounds(for: .mediaBox)

                let normalized = rects.map { rect -> NormalizedRect in
                    let x = (rect.minX - pageBounds.minX) / max(1, pageBounds.width)
                    let y = (rect.minY - pageBounds.minY) / max(1, pageBounds.height)
                    let w = rect.width / max(1, pageBounds.width)
                    let h = rect.height / max(1, pageBounds.height)
                    return NormalizedRect(x: Double(x), y: Double(y), w: Double(w), h: Double(h))
                }

                return PDFHighlightFragment(pageIndex: pageIndex, rects: normalized)
            }

        guard fragments.isEmpty == false else { return nil }
        return (PDFHighlightAnchor(fragments: fragments), quote)
    }
}
