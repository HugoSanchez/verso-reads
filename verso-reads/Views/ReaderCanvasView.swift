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

    @Binding var isRightPanelVisible: Bool
    @Binding var activeDocument: LibraryDocument?
    @Binding var pdfDocument: PDFDocument?

    @StateObject private var pdfController = PDFReaderController()
    @State private var highlights: [Annotation] = []
    @State private var highlightColor: HighlightColor = .yellow

    var body: some View {
        VStack(spacing: 0) {
            ReaderToolbar(
                title: readerTitle,
                isRightPanelVisible: $isRightPanelVisible,
                highlightColor: $highlightColor,
                onHighlight: { addHighlight(color: $0) }
            )

            // Content area (will show document or empty state)
            Group {
                if let pdfDocument {
                    PDFKitView(
                        document: pdfDocument,
                        highlights: highlights,
                        controller: pdfController
                    )
                        .background(Color.white)
                } else {
                    EmptyReaderState(onOpen: openPDF, onDrop: handleDrop)
                }
            }
        }
        .onAppear {
            loadHighlights()
        }
        .onChange(of: activeDocument?.id) { _, _ in
            loadHighlights()
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
}

#Preview {
    ReaderCanvasView(
        isRightPanelVisible: .constant(false),
        activeDocument: .constant(nil),
        pdfDocument: .constant(nil)
    )
    .modelContainer(for: [LibraryDocument.self, Annotation.self], inMemory: true)
    .frame(width: 800, height: 600)
    .background(Color.white)
}
