//
//  ReaderCanvasView.swift
//  verso-reads
//

import SwiftUI
import PDFKit
import SwiftData
import UniformTypeIdentifiers

struct ReaderCanvasView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var readerSession: ReaderSession
    @Query(sort: \Annotation.createdAt, order: .forward) private var annotations: [Annotation]

    @Binding var isSidebarVisible: Bool
    @Binding var isRightPanelVisible: Bool
    @Binding var activeDocument: LibraryDocument?
    @Binding var pdfDocument: PDFDocument?
    @Binding var activePinAnchor: Data?
    let onAddSelectionToChat: (ChatContext) -> Void
    let onShowPinnedAnswer: (Annotation) -> Void
    let onTogglePinHighlight: () -> Void
    let onClearPinHighlight: () -> Void
    let selectionDismiss: SelectionDismissController

    @StateObject private var pdfController = PDFReaderController()
    @State private var highlightColor: HighlightColor = .yellow
    @State private var lastSelectionInfo: PDFReaderController.SelectionInfo?

    var body: some View {
        VStack(spacing: 0) {
            ReaderToolbar(
                title: readerTitle,
                isTitleEditable: activeDocument != nil,
                onTitleCommit: renameActiveDocument,
                isSidebarVisible: $isSidebarVisible,
                onSidebarToggle: { _ in
                    pdfController.captureDesiredScaleFactorIfNeeded()
                },
                isRightPanelVisible: $isRightPanelVisible,
                highlightColor: $highlightColor,
                onHighlight: { addHighlight(color: $0) },
                onRightPanelToggle: { _ in
                    pdfController.captureDesiredScaleFactorIfNeeded()
                },
                isZoomEnabled: pdfDocument != nil,
                currentZoomPercent: {
                    Double(pdfController.currentScaleFactor() ?? 1.0) * 100
                },
                onApplyZoomPercent: { percent in
                    pdfController.setScaleFactor(CGFloat(percent / 100))
                }
            )

            // Content area (will show document or empty state)
            Group {
                if let pdfDocument {
                    GeometryReader { proxy in
                        ZStack(alignment: .topLeading) {
                            PDFKitView(
                                document: pdfDocument,
                                highlights: highlightAnnotations,
                                chatPins: chatPinAnnotations,
                                activePinAnchor: activePinAnchor ?? readerSession.activeNoteQuoteAnchor,
                                controller: pdfController,
                                availableWidth: proxy.size.width,
                                onPinTapped: handlePinTapped
                            )
                            selectionOverlay(in: proxy.size)
                        }
                    }
                    .background(Color.white)
                } else {
                    EmptyReaderState(onOpen: openPDF, onDrop: handleDrop)
                }
            }
        }
        .onAppear {
            selectionDismiss.clearSelection = { pdfController.clearSelection() }
        }
        .onReceive(pdfController.$selectionInfo) { selection in
            selectionDismiss.isActive = selection != nil
            if let selection {
                lastSelectionInfo = selection
            }
        }
        .onReceive(readerSession.noteQuoteNavigation) { annotationID in
            navigateToNoteQuote(annotationID)
        }
        .onChange(of: activeDocument?.id) { _, _ in
            lastSelectionInfo = nil
        }
    }

    private var readerTitle: String {
        if let activeDocument {
            return activeDocument.title
        }

        guard let url = pdfDocument?.documentURL else { return "New reading" }
        return url.deletingPathExtension().lastPathComponent
    }

    private func openPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            importAndOpenPDF(from: url)
        }
    }

    private func handleDrop(url: URL) {
        importAndOpenPDF(from: url)
    }

    private func importAndOpenPDF(from url: URL) {
        do {
            let document = try LibraryStore.importDocument(from: url, modelContext: modelContext)
            let storedURL = try LibraryStore.fileURL(for: document)
            activeDocument = document
            pdfDocument = PDFDocument(url: storedURL)
            Task {
                await RAGIngestionManager.shared.enqueue(document: document, fileURL: storedURL)
            }
        } catch {
            print("Failed to import PDF: \(error)")
            activeDocument = nil
            pdfDocument = PDFDocument(url: url)
        }
    }

    private func renameActiveDocument(to newTitle: String) {
        guard let activeDocument else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        activeDocument.title = trimmed
        do {
            try modelContext.save()
        } catch {
            print("Failed to rename document: \(error)")
        }
    }

    private func addHighlight(color: HighlightColor) {
        guard let documentID = activeDocument?.id else { return }
        guard let result = pdfController.makeHighlightAnchorFromSelection() else { return }

        do {
            let data = try JSONEncoder().encode(result.anchor)
            let annotation = Annotation(
                documentID: documentID,
                kind: .highlight,
                anchorData: data,
                quote: result.quote,
                colorRawValue: color.rawValue
            )
            modelContext.insert(annotation)
            try modelContext.save()
            pdfController.clearSelection()
        } catch {
            print("Failed to save highlight: \(error)")
        }
    }

    @ViewBuilder
    private func selectionOverlay(in size: CGSize) -> some View {
        if let selection = pdfController.selectionInfo {
            let position = selectionOverlayPosition(for: selection.rect, in: size)
            HStack(spacing: 8) {
                selectionActionButton(
                    title: "Add to chat",
                    systemImage: "plus",
                    action: {
#if DEBUG
                        print("[Chat] add-to-chat tapped selectionTextCount=\(selection.text.count)")
#endif
                        if let anchorData = try? JSONEncoder().encode(selection.anchor) {
#if DEBUG
                            print("[Chat] anchor created fragments=\(selection.anchor.fragments.count) quoteCount=\(selection.quote.count)")
#endif
                            onAddSelectionToChat(ChatContext(text: selection.text, anchorData: anchorData))
                        } else {
#if DEBUG
                            print("[Chat] anchor creation failed")
#endif
                            onAddSelectionToChat(ChatContext(text: selection.text))
                        }
                        pdfController.clearSelection()
                    }
                )

                selectionActionButton(
                    title: "Add to notes",
                    systemImage: "note.text",
                    action: addSelectionToNotes
                )
            }
            .position(position)
        }
    }

    private func handlePinTapped(_ pinID: UUID) {
        guard let annotation = chatPinAnnotations.first(where: { $0.id == pinID }) else { return }

        // Clear any active note quote highlight
        readerSession.activeNoteQuoteAnchor = nil

        // If tapping the same pin that's already shown, just toggle the highlight
        if let currentAnchor = activePinAnchor, currentAnchor == annotation.anchorData {
            onTogglePinHighlight()
            return
        }

        // Show new pinned answer
        onShowPinnedAnswer(annotation)
    }

    private func selectionActionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func selectionOverlayPosition(for rect: CGRect, in size: CGSize) -> CGPoint {
        let padding: CGFloat = 10
        let fallbackWidth: CGFloat = 220
        let fallbackHeight: CGFloat = 26

        var x = rect.midX
        var y = rect.minY - 12

        if x + fallbackWidth / 2 > size.width - padding {
            x = size.width - padding - fallbackWidth / 2
        }
        if x - fallbackWidth / 2 < padding {
            x = padding + fallbackWidth / 2
        }

        if y - fallbackHeight / 2 < padding {
            y = rect.maxY + 14
        }
        if y + fallbackHeight / 2 > size.height - padding {
            y = size.height - padding - fallbackHeight / 2
        }

        return CGPoint(x: x, y: y)
    }

    private func addSelectionToNotes() {
        guard let documentID = activeDocument?.id else { return }
        guard let selection = pdfController.selectionInfo ?? lastSelectionInfo else { return }

        do {
            let data = try JSONEncoder().encode(selection.anchor)
            let annotation = Annotation(
                documentID: documentID,
                kind: .noteQuote,
                anchorData: data,
                quote: selection.quote
            )
            modelContext.insert(annotation)
            try modelContext.save()
            readerSession.pendingNoteQuote = NoteQuoteInsertion(
                annotationID: annotation.id,
                documentID: documentID,
                quote: selection.quote
            )
            print("[NoteQuote] Saved annotation=\(annotation.id) doc=\(documentID)")
            isRightPanelVisible = true
            pdfController.clearSelection()
        } catch {
            print("Failed to save note quote: \(error)")
        }
    }

    private func navigateToNoteQuote(_ annotationID: UUID) {
        do {
            let predicate = #Predicate<Annotation> { annotation in
                annotation.id == annotationID
            }
            var descriptor = FetchDescriptor<Annotation>(predicate: predicate)
            descriptor.fetchLimit = 1
            guard let annotation = try modelContext.fetch(descriptor).first else { return }
            guard annotation.kind == .noteQuote else { return }
            let anchor = try JSONDecoder().decode(PDFHighlightAnchor.self, from: annotation.anchorData)
            print("[NoteQuote] Navigate id=\(annotationID) fragments=\(anchor.fragments.count)")

            // Toggle highlight if clicking the same quote, otherwise show new highlight
            if readerSession.activeNoteQuoteAnchor == annotation.anchorData {
                readerSession.activeNoteQuoteAnchor = nil
            } else {
                // Clear pin highlight and show note quote highlight
                onClearPinHighlight()
                readerSession.activeNoteQuoteAnchor = annotation.anchorData
                pdfController.scrollTo(anchor: anchor)
            }
        } catch {
            print("Failed to navigate to note quote: \(error)")
        }
    }

    private var filteredAnnotations: [Annotation] {
        guard let documentID = activeDocument?.id else { return [] }
        return annotations.filter { annotation in
            annotation.documentID == documentID &&
            (annotation.kind == .highlight || annotation.kind == .chatPin)
        }
    }

    private var highlightAnnotations: [Annotation] {
        filteredAnnotations.filter { $0.kind == .highlight }
    }

    private var chatPinAnnotations: [Annotation] {
        filteredAnnotations.filter { $0.kind == .chatPin }
    }
}

#Preview {
    ReaderCanvasView(
        isSidebarVisible: .constant(true),
        isRightPanelVisible: .constant(false),
        activeDocument: .constant(nil),
        pdfDocument: .constant(nil),
        activePinAnchor: .constant(nil),
        onAddSelectionToChat: { _ in },
        onShowPinnedAnswer: { _ in },
        onTogglePinHighlight: {},
        onClearPinHighlight: {},
        selectionDismiss: SelectionDismissController()
    )
    .modelContainer(for: [LibraryDocument.self, Annotation.self], inMemory: true)
    .environmentObject(ReaderSession())
    .frame(width: 800, height: 600)
    .background(Color.white)
}
