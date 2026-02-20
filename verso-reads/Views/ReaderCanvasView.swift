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

    @Binding var isSidebarVisible: Bool
    @Binding var isRightPanelVisible: Bool
    @Binding var activeDocument: LibraryDocument?
    @Binding var pdfDocument: PDFDocument?
    let onAddSelectionToChat: (ChatContext) -> Void
    let selectionDismiss: SelectionDismissController

    @StateObject private var pdfController = PDFReaderController()
    @State private var highlights: [Annotation] = []
    @State private var highlightColor: HighlightColor = .yellow

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
                                highlights: highlights,
                                controller: pdfController,
                                availableWidth: proxy.size.width
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
            loadHighlights()
            selectionDismiss.clearSelection = { pdfController.clearSelection() }
        }
        .onChange(of: activeDocument?.id) { _, _ in
            loadHighlights()
        }
        .onReceive(pdfController.$selectionInfo) { selection in
            selectionDismiss.isActive = selection != nil
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
            loadHighlights()
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

    private func loadHighlights() {
        guard let documentID = activeDocument?.id else {
            highlights = []
            return
        }

        do {
            let predicate = #Predicate<Annotation> { annotation in
                annotation.documentID == documentID && annotation.kindRawValue == "highlight"
            }
            var descriptor = FetchDescriptor<Annotation>(predicate: predicate)
            descriptor.sortBy = [SortDescriptor(\Annotation.createdAt, order: .forward)]
            highlights = try modelContext.fetch(descriptor)
        } catch {
            print("Failed to load highlights: \(error)")
            highlights = []
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
            highlights.append(annotation)
            pdfController.clearSelection()
        } catch {
            print("Failed to save highlight: \(error)")
        }
    }

    @ViewBuilder
    private func selectionOverlay(in size: CGSize) -> some View {
        if let selection = pdfController.selectionInfo {
            let position = selectionOverlayPosition(for: selection.rect, in: size)
            Button {
                onAddSelectionToChat(ChatContext(text: selection.text))
                pdfController.clearSelection()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Add to chat")
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
            .position(position)
        }
    }

    private func selectionOverlayPosition(for rect: CGRect, in size: CGSize) -> CGPoint {
        let padding: CGFloat = 10
        let fallbackWidth: CGFloat = 120
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
}

#Preview {
    ReaderCanvasView(
        isSidebarVisible: .constant(true),
        isRightPanelVisible: .constant(false),
        activeDocument: .constant(nil),
        pdfDocument: .constant(nil),
        onAddSelectionToChat: { _ in },
        selectionDismiss: SelectionDismissController()
    )
    .modelContainer(for: [LibraryDocument.self, Annotation.self], inMemory: true)
    .frame(width: 800, height: 600)
    .background(Color.white)
}
