//
//  PDFKitView.swift
//  verso-reads
//

import SwiftUI
import PDFKit

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    let highlights: [Annotation]
    let controller: PDFReaderController

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.pageBreakMargins = NSEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
        view.backgroundColor = NSColor(white: 0.97, alpha: 1.0)
        view.displaysAsBook = false
        view.pageShadowsEnabled = false
        hideScrollbars(in: view)
        DispatchQueue.main.async {
            hideScrollbars(in: view)
        }
        controller.attach(pdfView: view)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
            context.coordinator.reset()
        }
        nsView.pageShadowsEnabled = false
        hideScrollbars(in: nsView)
        DispatchQueue.main.async {
            hideScrollbars(in: nsView)
        }
        controller.attach(pdfView: nsView)
        context.coordinator.sync(highlights: highlights, in: nsView)
    }

    private func hideScrollbars(in view: PDFView) {
        let scrollView = view.enclosingScrollView ?? findScrollView(in: view)
        guard let scrollView else { return }
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.alphaValue = 0
        scrollView.horizontalScroller?.alphaValue = 0
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let found = findScrollView(in: subview) {
                return found
            }
        }
        return nil
    }

    final class Coordinator: NSObject {
        private var appliedHighlightIDs: Set<UUID> = []
        private var pdfAnnotationsByHighlightID: [UUID: [PDFAnnotation]] = [:]

        func reset() {
            appliedHighlightIDs.removeAll()
            pdfAnnotationsByHighlightID.removeAll()
        }

        func sync(highlights: [Annotation], in pdfView: PDFView) {
            guard let document = pdfView.document else { return }

            let desiredIDs = Set(highlights.map(\.id))
            let removedIDs = appliedHighlightIDs.subtracting(desiredIDs)
            for removedID in removedIDs {
                removeHighlight(id: removedID, from: document)
            }

            for highlight in highlights {
                guard appliedHighlightIDs.contains(highlight.id) == false else { continue }
                guard highlight.kind == .highlight else { continue }
                applyHighlight(highlight, to: document)
            }
        }

        private func applyHighlight(_ highlight: Annotation, to document: PDFDocument) {
            guard let anchor = try? JSONDecoder().decode(PDFHighlightAnchor.self, from: highlight.anchorData) else { return }
            let color = HighlightColor(rawValue: highlight.colorRawValue ?? "")?.annotationNSColor ?? HighlightColor.yellow.annotationNSColor

            var created: [PDFAnnotation] = []
            for fragment in anchor.fragments {
                guard let page = document.page(at: fragment.pageIndex) else { continue }
                let pageBounds = page.bounds(for: .mediaBox)
                for rect in fragment.rects {
                    let bounds = CGRect(
                        x: pageBounds.minX + CGFloat(rect.x) * pageBounds.width,
                        y: pageBounds.minY + CGFloat(rect.y) * pageBounds.height,
                        width: CGFloat(rect.w) * pageBounds.width,
                        height: CGFloat(rect.h) * pageBounds.height
                    )
                    let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                    annotation.color = color
                    page.addAnnotation(annotation)
                    created.append(annotation)
                }
            }

            appliedHighlightIDs.insert(highlight.id)
            pdfAnnotationsByHighlightID[highlight.id] = created
        }

        private func removeHighlight(id: UUID, from document: PDFDocument) {
            guard let annotations = pdfAnnotationsByHighlightID[id] else { return }
            for annotation in annotations {
                annotation.page?.removeAnnotation(annotation)
            }
            pdfAnnotationsByHighlightID[id] = nil
            appliedHighlightIDs.remove(id)
        }
    }
}

#Preview {
    PDFKitView(document: PDFDocument(), highlights: [], controller: PDFReaderController())
        .frame(width: 600, height: 400)
}
