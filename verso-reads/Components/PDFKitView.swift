//
//  PDFKitView.swift
//  verso-reads
//

import SwiftUI
import PDFKit

struct HighlightTapInfo {
    let highlightID: UUID
    let screenRect: CGRect
}

struct NoteQuoteTapInfo {
    let quoteID: UUID
    let screenRect: CGRect
}

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    let highlights: [Annotation]
    let chatPins: [Annotation]
    let noteQuotes: [Annotation]
    let activePinAnchor: Data?
    let controller: PDFReaderController
    let availableWidth: CGFloat
    let onPinTapped: (UUID) -> Void
    let onNoteQuoteTapped: (NoteQuoteTapInfo) -> Void
    let onHighlightTapped: (HighlightTapInfo) -> Void
    let onBackgroundTapped: () -> Void

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
            pinView.onNoteQuoteTapped = onNoteQuoteTapped
            pinView.onHighlightTapped = onHighlightTapped
            pinView.onBackgroundTapped = onBackgroundTapped
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
            pinView.onNoteQuoteTapped = onNoteQuoteTapped
            pinView.onHighlightTapped = onHighlightTapped
            pinView.onBackgroundTapped = onBackgroundTapped
        }
        context.coordinator.sync(highlights: highlights, pins: chatPins, noteQuotes: noteQuotes, activePinAnchor: activePinAnchor, in: nsView)
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
        private var appliedHighlightColors: [UUID: String] = [:]
        private var pdfAnnotationsByHighlightID: [UUID: [PDFAnnotation]] = [:]
        private var appliedPinIDs: Set<UUID> = []
        private var pdfAnnotationsByPinID: [UUID: PDFAnnotation] = [:]
        private var appliedNoteQuoteIDs: Set<UUID> = []
        private var pdfAnnotationsByNoteQuoteID: [UUID: PDFAnnotation] = [:]
        private var activePinHighlightAnnotations: [PDFAnnotation] = []
        private var currentActivePinAnchor: Data?

        func reset() {
            appliedHighlightIDs.removeAll()
            appliedHighlightColors.removeAll()
            pdfAnnotationsByHighlightID.removeAll()
            appliedPinIDs.removeAll()
            pdfAnnotationsByPinID.removeAll()
            appliedNoteQuoteIDs.removeAll()
            pdfAnnotationsByNoteQuoteID.removeAll()
            activePinHighlightAnnotations.removeAll()
            currentActivePinAnchor = nil
        }

        func sync(highlights: [Annotation], pins: [Annotation], noteQuotes: [Annotation], activePinAnchor: Data?, in pdfView: PDFView) {
            guard let document = pdfView.document else { return }

            let desiredIDs = Set(highlights.map(\.id))
            let removedIDs = appliedHighlightIDs.subtracting(desiredIDs)
            for removedID in removedIDs {
                removeHighlight(id: removedID, from: document)
            }

            for highlight in highlights {
                guard highlight.kind == .highlight else { continue }

                // Check if color changed - if so, remove and re-apply
                let currentColor = highlight.colorRawValue ?? ""
                if appliedHighlightIDs.contains(highlight.id) {
                    if appliedHighlightColors[highlight.id] != currentColor {
                        removeHighlight(id: highlight.id, from: document)
                    } else {
                        continue
                    }
                }

                applyHighlight(highlight, to: document)
                appliedHighlightColors[highlight.id] = currentColor
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

            // Sync note quote markers
            let desiredNoteQuoteIDs = Set(noteQuotes.map(\.id))
            let removedNoteQuoteIDs = appliedNoteQuoteIDs.subtracting(desiredNoteQuoteIDs)
            if !removedNoteQuoteIDs.isEmpty {
                print("[PDFKitView] removing note quote markers: \(removedNoteQuoteIDs)")
            }
            for removedID in removedNoteQuoteIDs {
                removeNoteQuote(id: removedID, from: document, pdfView: pdfView)
            }

            for noteQuote in noteQuotes {
                guard appliedNoteQuoteIDs.contains(noteQuote.id) == false else { continue }
                guard noteQuote.kind == .noteQuote else { continue }
                applyNoteQuote(noteQuote, to: document)
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
                    annotation.userName = highlight.id.uuidString
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

        private func applyNoteQuote(_ noteQuote: Annotation, to document: PDFDocument) {
            guard let anchor = try? JSONDecoder().decode(PDFHighlightAnchor.self, from: noteQuote.anchorData) else { return }
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

            let markerSize: CGFloat = 14
            let margin: CGFloat = 6
            let gap: CGFloat = 10
            let horizontalOffset: CGFloat = 18 // Offset to the right of pins

            var x = unionRect.maxX + gap + horizontalOffset
            if x + markerSize > pageBounds.maxX - margin {
                x = max(pageBounds.minX + margin, pageBounds.maxX - margin - markerSize)
            }
            var y = unionRect.midY - markerSize / 2
            y = min(max(y, pageBounds.minY + margin), pageBounds.maxY - margin - markerSize)

            let markerBounds = CGRect(x: x, y: y, width: markerSize, height: markerSize)
            let annotation = NoteQuotePDFAnnotation(bounds: markerBounds, quoteID: noteQuote.id)
            annotation.shouldPrint = false
            annotation.userName = noteQuote.id.uuidString
            page.addAnnotation(annotation)

            appliedNoteQuoteIDs.insert(noteQuote.id)
            pdfAnnotationsByNoteQuoteID[noteQuote.id] = annotation
        }

        private func removeNoteQuote(id: UUID, from document: PDFDocument, pdfView: PDFView? = nil) {
            print("[PDFKitView] removeNoteQuote called for: \(id)")
            guard let annotation = pdfAnnotationsByNoteQuoteID[id] else {
                print("[PDFKitView] annotation not found in cache!")
                return
            }

            // Clear from our tracking first
            pdfAnnotationsByNoteQuoteID[id] = nil
            appliedNoteQuoteIDs.remove(id)

            guard let page = annotation.page else {
                print("[PDFKitView] annotation has no page!")
                return
            }

            print("[PDFKitView] removing annotation from page, page has \(page.annotations.count) annotations")

            // Hide annotation first, then remove
            annotation.shouldDisplay = false
            page.removeAnnotation(annotation)

            print("[PDFKitView] after removal, page has \(page.annotations.count) annotations")

            // Force complete redraw
            DispatchQueue.main.async {
                pdfView?.layoutDocumentView()
                pdfView?.needsDisplay = true
                pdfView?.documentView?.needsDisplay = true
                pdfView?.setNeedsDisplay(pdfView?.bounds ?? .zero)
            }
            print("[PDFKitView] removal complete")
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
        noteQuotes: [],
        activePinAnchor: nil,
        controller: PDFReaderController(),
        availableWidth: 800,
        onPinTapped: { _ in },
        onNoteQuoteTapped: { (_: NoteQuoteTapInfo) in },
        onHighlightTapped: { (_: HighlightTapInfo) in },
        onBackgroundTapped: {}
    )
        .frame(width: 600, height: 400)
}

final class PinPDFView: PDFView {
    var onPinTapped: ((UUID) -> Void)?
    var onNoteQuoteTapped: ((NoteQuoteTapInfo) -> Void)?
    var onHighlightTapped: ((HighlightTapInfo) -> Void)?
    var onBackgroundTapped: (() -> Void)?
    private var isShowingPointingHand = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Remove existing tracking areas
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        // Add tracking area for mouse movement
        let options: NSTrackingArea.Options = [.mouseMoved, .activeInKeyWindow, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        var shouldShowPointer = false

        if let page = page(for: location, nearest: true) {
            let pagePoint = convert(location, to: page)
            // Check for any clickable annotation
            if page.annotation(at: pagePoint) is PinPDFAnnotation {
                shouldShowPointer = true
            } else if page.annotation(at: pagePoint) is NoteQuotePDFAnnotation {
                shouldShowPointer = true
            } else if let annotation = page.annotation(at: pagePoint),
                      annotation.type == "Highlight",
                      annotation.userName != nil {
                shouldShowPointer = true
            }
        }

        if shouldShowPointer && !isShowingPointingHand {
            NSCursor.pointingHand.push()
            isShowingPointingHand = true
        } else if !shouldShowPointer && isShowingPointingHand {
            NSCursor.pop()
            isShowingPointingHand = false
        }

        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        if isShowingPointingHand {
            NSCursor.pop()
            isShowingPointingHand = false
        }
        super.mouseExited(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if let page = page(for: location, nearest: true) {
            let pagePoint = convert(location, to: page)
            if let pinAnnotation = page.annotation(at: pagePoint) as? PinPDFAnnotation {
                onPinTapped?(pinAnnotation.pinID)
                return
            }
            if let quoteAnnotation = page.annotation(at: pagePoint) as? NoteQuotePDFAnnotation {
                // Convert annotation bounds to view coordinates for delete button positioning
                let pageBounds = quoteAnnotation.bounds
                let viewRect = convert(pageBounds, from: page)
                // Flip Y coordinate if view is not flipped
                let adjustedRect: CGRect
                if isFlipped {
                    adjustedRect = viewRect
                } else {
                    adjustedRect = CGRect(
                        x: viewRect.minX,
                        y: bounds.height - viewRect.maxY,
                        width: viewRect.width,
                        height: viewRect.height
                    )
                }
                onNoteQuoteTapped?(NoteQuoteTapInfo(quoteID: quoteAnnotation.quoteID, screenRect: adjustedRect))
                return
            }
            // Check for highlight annotation
            if let annotation = page.annotation(at: pagePoint),
               annotation.type == "Highlight",
               let userName = annotation.userName,
               let highlightID = UUID(uuidString: userName) {
                // Convert annotation bounds to view coordinates for popover positioning
                let pageBounds = annotation.bounds
                let viewRect = convert(pageBounds, from: page)
                // Flip Y coordinate if view is not flipped (same as PDFReaderController does)
                let adjustedRect: CGRect
                if isFlipped {
                    adjustedRect = viewRect
                } else {
                    adjustedRect = CGRect(
                        x: viewRect.minX,
                        y: bounds.height - viewRect.maxY,
                        width: viewRect.width,
                        height: viewRect.height
                    )
                }
                onHighlightTapped?(HighlightTapInfo(highlightID: highlightID, screenRect: adjustedRect))
                return
            }
        }
        // No annotation tapped - notify to dismiss any popover
        onBackgroundTapped?()
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

        // Outer ring - subtle
        context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor)
        context.fillEllipse(in: rect)

        // Inner dot - more subtle
        let dotSize = rect.width * 0.4
        let dotRect = CGRect(
            x: rect.midX - dotSize / 2,
            y: rect.midY - dotSize / 2,
            width: dotSize,
            height: dotSize
        )
        context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor)
        context.fillEllipse(in: dotRect)

        context.restoreGState()
    }
}

final class NoteQuotePDFAnnotation: PDFAnnotation {
    let quoteID: UUID

    init(bounds: CGRect, quoteID: UUID) {
        self.quoteID = quoteID
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

        // Outer rounded rect (document/note style) - amber/orange color
        let noteColor = NSColor(red: 0.95, green: 0.6, blue: 0.1, alpha: 1.0)
        context.setFillColor(noteColor.withAlphaComponent(0.15).cgColor)
        let cornerRadius = rect.width * 0.2
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.addPath(path)
        context.fillPath()

        // Inner lines (document lines icon)
        context.setStrokeColor(noteColor.cgColor)
        context.setLineWidth(1.2)

        let lineInset = rect.width * 0.25
        let lineSpacing = rect.height * 0.22
        let centerY = rect.midY

        // Top line
        context.move(to: CGPoint(x: rect.minX + lineInset, y: centerY + lineSpacing))
        context.addLine(to: CGPoint(x: rect.maxX - lineInset, y: centerY + lineSpacing))
        context.strokePath()

        // Middle line
        context.move(to: CGPoint(x: rect.minX + lineInset, y: centerY))
        context.addLine(to: CGPoint(x: rect.maxX - lineInset, y: centerY))
        context.strokePath()

        // Bottom line (shorter)
        context.move(to: CGPoint(x: rect.minX + lineInset, y: centerY - lineSpacing))
        context.addLine(to: CGPoint(x: rect.maxX - lineInset * 1.5, y: centerY - lineSpacing))
        context.strokePath()

        context.restoreGState()
    }
}
