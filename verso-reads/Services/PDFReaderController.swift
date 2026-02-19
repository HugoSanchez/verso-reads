//
//  PDFReaderController.swift
//  verso-reads
//

import Foundation
import Combine
import PDFKit

@MainActor
final class PDFReaderController: NSObject, ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    weak var pdfView: PDFView?
    private var preferredScaleFactor: CGFloat?
    private var preferredScaleFactorExpiresAt: Date?
    @Published private(set) var selectionInfo: SelectionInfo?

    private weak var observedScrollView: NSScrollView?
    private weak var observedContentView: NSView?


    func attach(pdfView: PDFView) {
        if self.pdfView !== pdfView {
            stopObservingSelection()
            self.pdfView = pdfView
            startObservingSelection(in: pdfView)
        }
    }

    func capturePreferredScaleFactor() {
        guard let pdfView else { return }
        preferredScaleFactor = pdfView.scaleFactor
        preferredScaleFactorExpiresAt = Date().addingTimeInterval(0.35)
    }

    func resetPreferredScaleFactor() {
        preferredScaleFactor = nil
        preferredScaleFactorExpiresAt = nil
    }

    func applyPreferredScaleFactorIfNeeded(availableWidth: CGFloat) {
        if let preferredScaleFactorExpiresAt, Date() > preferredScaleFactorExpiresAt {
            resetPreferredScaleFactor()
            return
        }
        guard let pdfView, let preferredScaleFactor else { return }
        guard let fitWidthScale = fitWidthScaleFactor(for: pdfView, availableWidth: availableWidth) else { return }

        let clamped = min(preferredScaleFactor, fitWidthScale)
        pdfView.autoScales = false

        if abs(pdfView.scaleFactor - clamped) > 0.0001 {
            pdfView.scaleFactor = clamped
        }
    }

    func currentScaleFactor() -> CGFloat? {
        pdfView?.scaleFactor
    }

    func setScaleFactor(_ scaleFactor: CGFloat) {
        guard let pdfView else { return }
        resetPreferredScaleFactor()
        pdfView.autoScales = false
        pdfView.scaleFactor = scaleFactor
    }

    func zoomToActualSize() {
        setScaleFactor(1.0)
    }

    func zoomToFitWidth(availableWidth: CGFloat) {
        guard let pdfView else { return }
        guard let scaleFactor = fitWidthScaleFactor(for: pdfView, availableWidth: availableWidth) else { return }
        setScaleFactor(scaleFactor)
    }

    func clearSelection() {
        pdfView?.clearSelection()
        selectionInfo = nil
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

    private func startObservingSelection(in pdfView: PDFView) {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleSelectionChanged), name: .PDFViewSelectionChanged, object: pdfView)
        center.addObserver(self, selector: #selector(handleScaleChanged), name: .PDFViewScaleChanged, object: pdfView)
        center.addObserver(self, selector: #selector(handleVisiblePagesChanged), name: .PDFViewVisiblePagesChanged, object: pdfView)

        if let scrollView = pdfView.enclosingScrollView {
            observedScrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            observedContentView = scrollView.contentView
            center.addObserver(self, selector: #selector(handleBoundsChanged), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        }

        updateSelectionInfo()
    }

    private func stopObservingSelection() {
        NotificationCenter.default.removeObserver(self)
        observedScrollView = nil
        observedContentView = nil
        selectionInfo = nil
    }

    @objc private func handleSelectionChanged() {
        updateSelectionInfo()
    }

    @objc private func handleScaleChanged() {
        updateSelectionInfo()
    }

    @objc private func handleVisiblePagesChanged() {
        updateSelectionInfo()
    }

    @objc private func handleBoundsChanged() {
        updateSelectionInfo()
    }

    private func updateSelectionInfo() {
        guard let pdfView else {
            selectionInfo = nil
            return
        }
        guard let selection = pdfView.currentSelection,
              let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.isEmpty == false
        else {
            selectionInfo = nil
            return
        }

        let unionRect = selectionBoundsInView(selection: selection, pdfView: pdfView)
        guard unionRect.isNull == false, unionRect.isEmpty == false else {
            selectionInfo = nil
            return
        }
        guard pdfView.bounds.intersects(unionRect) else {
            selectionInfo = nil
            return
        }

        let adjustedRect: CGRect
        if pdfView.isFlipped {
            adjustedRect = unionRect
        } else {
            adjustedRect = CGRect(
                x: unionRect.minX,
                y: pdfView.bounds.height - unionRect.maxY,
                width: unionRect.width,
                height: unionRect.height
            )
        }

        selectionInfo = SelectionInfo(text: text, rect: adjustedRect)
    }

    private func selectionBoundsInView(selection: PDFSelection, pdfView: PDFView) -> CGRect {
        guard let document = pdfView.document else { return .null }
        var unionRect = CGRect.null

        for page in selection.pages {
            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound else { continue }
            let bounds = selection.bounds(for: page)
            guard bounds.isNull == false, bounds.isEmpty == false else { continue }
            let viewRect = pdfView.convert(bounds, from: page)
            unionRect = unionRect.union(viewRect)
        }

        return unionRect
    }

    struct SelectionInfo: Equatable {
        let text: String
        let rect: CGRect
    }

    private func fitWidthScaleFactor(for pdfView: PDFView, availableWidth: CGFloat) -> CGFloat? {
        guard let document = pdfView.document else { return nil }
        let page = pdfView.currentPage ?? document.page(at: 0)
        guard let page else { return nil }

        let pageBounds = page.bounds(for: .mediaBox)
        guard pageBounds.width > 0 else { return nil }

        let scrollWidth = pdfView.enclosingScrollView?.contentView.bounds.width ?? availableWidth
        let safeWidth = max(0, scrollWidth - 2)
        guard safeWidth > 0 else { return nil }
        return safeWidth / pageBounds.width
    }
}
