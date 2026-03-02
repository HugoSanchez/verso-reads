//
//  PDFKitView.swift
//  verso-reads
//

import SwiftUI
import PDFKit

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    let highlights: [Annotation]
    let chatPins: [Annotation]
    let activePinAnchor: Data?
    let controller: PDFReaderController
    let availableWidth: CGFloat
    let onPinTapped: (UUID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PinPDFView()
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
        if let pinView = view as? PinPDFView {
            pinView.onPinTapped = onPinTapped
        }
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
            context.coordinator.reset()
            nsView.autoScales = true
            controller.resetDesiredScaleFactor()
        }
        nsView.pageShadowsEnabled = false
        hideScrollbars(in: nsView)
        DispatchQueue.main.async {
            hideScrollbars(in: nsView)
        }
        controller.attach(pdfView: nsView)
        controller.applyDesiredScaleFactorIfNeeded(availableWidth: availableWidth)
        if let pinView = nsView as? PinPDFView {
            pinView.onPinTapped = onPinTapped
        }
        context.coordinator.sync(highlights: highlights, pins: chatPins, activePinAnchor: activePinAnchor, in: nsView)
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
        private var appliedPinIDs: Set<UUID> = []
        private var pdfAnnotationsByPinID: [UUID: PDFAnnotation] = [:]
        private var activePinHighlightAnnotations: [PDFAnnotation] = []
        private var currentActivePinAnchor: Data?

        func reset() {
            appliedHighlightIDs.removeAll()
            pdfAnnotationsByHighlightID.removeAll()
            appliedPinIDs.removeAll()
            pdfAnnotationsByPinID.removeAll()
            activePinHighlightAnnotations.removeAll()
            currentActivePinAnchor = nil
        }

        func sync(highlights: [Annotation], pins: [Annotation], activePinAnchor: Data?, in pdfView: PDFView) {
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

            let desiredPinIDs = Set(pins.map(\.id))
            let removedPinIDs = appliedPinIDs.subtracting(desiredPinIDs)
            for removedID in removedPinIDs {
                removePin(id: removedID, from: document)
            }

            for pin in pins {
                guard appliedPinIDs.contains(pin.id) == false else { continue }
                guard pin.kind == .chatPin else { continue }
                applyPin(pin, to: document)
            }

            // Handle active pin temporary highlight
            if activePinAnchor != currentActivePinAnchor {
                removeActivePinHighlight(from: document)
                currentActivePinAnchor = activePinAnchor
                if let anchorData = activePinAnchor {
                    applyActivePinHighlight(anchorData: anchorData, to: document)
                }
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

        private func applyPin(_ pin: Annotation, to document: PDFDocument) {
            guard let anchor = try? JSONDecoder().decode(PDFHighlightAnchor.self, from: pin.anchorData) else { return }
            guard let firstFragment = anchor.fragments.sorted(by: { $0.pageIndex < $1.pageIndex }).first,
                  let page = document.page(at: firstFragment.pageIndex),
                  firstFragment.rects.isEmpty == false
            else { return }

            let pageBounds = page.bounds(for: .mediaBox)
            let unionRect = firstFragment.rects.reduce(into: CGRect.null) { rect, normalized in
                let bounds = CGRect(
                    x: pageBounds.minX + CGFloat(normalized.x) * pageBounds.width,
                    y: pageBounds.minY + CGFloat(normalized.y) * pageBounds.height,
                    width: CGFloat(normalized.w) * pageBounds.width,
                    height: CGFloat(normalized.h) * pageBounds.height
                )
                rect = rect.union(bounds)
            }

            guard unionRect.isNull == false, unionRect.isEmpty == false else { return }

            let pinSize: CGFloat = 14
            let margin: CGFloat = 6
            let gap: CGFloat = 10
            var x = unionRect.maxX + gap
            if x + pinSize > pageBounds.maxX - margin {
                x = max(pageBounds.minX + margin, pageBounds.maxX - margin - pinSize)
            }
            var y = unionRect.midY - pinSize / 2
            y = min(max(y, pageBounds.minY + margin), pageBounds.maxY - margin - pinSize)

            let pinBounds = CGRect(x: x, y: y, width: pinSize, height: pinSize)
            let annotation = PinPDFAnnotation(bounds: pinBounds, pinID: pin.id)
            annotation.shouldPrint = false
            annotation.userName = pin.id.uuidString
            page.addAnnotation(annotation)

            appliedPinIDs.insert(pin.id)
            pdfAnnotationsByPinID[pin.id] = annotation
        }

        private func removePin(id: UUID, from document: PDFDocument) {
            guard let annotation = pdfAnnotationsByPinID[id] else { return }
            annotation.page?.removeAnnotation(annotation)
            pdfAnnotationsByPinID[id] = nil
            appliedPinIDs.remove(id)
        }

        private func applyActivePinHighlight(anchorData: Data, to document: PDFDocument) {
            guard let anchor = try? JSONDecoder().decode(PDFHighlightAnchor.self, from: anchorData) else { return }

            let highlightColor = NSColor.controlAccentColor.withAlphaComponent(0.25)

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
                    annotation.color = highlightColor
                    page.addAnnotation(annotation)
                    activePinHighlightAnnotations.append(annotation)
                }
            }
        }

        private func removeActivePinHighlight(from document: PDFDocument) {
            for annotation in activePinHighlightAnnotations {
                annotation.page?.removeAnnotation(annotation)
            }
            activePinHighlightAnnotations.removeAll()
        }
    }
}

#Preview {
    PDFKitView(
        document: PDFDocument(),
        highlights: [],
        chatPins: [],
        activePinAnchor: nil,
        controller: PDFReaderController(),
        availableWidth: 800,
        onPinTapped: { _ in }
    )
        .frame(width: 600, height: 400)
}

final class PinPDFView: PDFView {
    var onPinTapped: ((UUID) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if let page = page(for: location, nearest: true) {
            let pagePoint = convert(location, to: page)
            if let annotation = page.annotation(at: pagePoint) as? PinPDFAnnotation {
                onPinTapped?(annotation.pinID)
                return
            }
        }
        super.mouseDown(with: event)
    }
}

final class PinPDFAnnotation: PDFAnnotation {
    let pinID: UUID

    init(bounds: CGRect, pinID: UUID) {
        self.pinID = pinID
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
        color = .clear
        shouldDisplay = true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.saveGState()

        let rect = bounds.insetBy(dx: 1, dy: 1)

        // Outer ring
        context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor)
        context.fillEllipse(in: rect)

        // Inner dot
        let dotSize = rect.width * 0.45
        let dotRect = CGRect(
            x: rect.midX - dotSize / 2,
            y: rect.midY - dotSize / 2,
            width: dotSize,
            height: dotSize
        )
        context.setFillColor(NSColor.controlAccentColor.cgColor)
        context.fillEllipse(in: dotRect)

        context.restoreGState()
    }
}
