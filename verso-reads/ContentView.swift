//
//  ContentView.swift
//  verso-reads
//
//  Created by Hugo Sanchez on 12/2/26.
//

import SwiftUI
import PDFKit
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LibraryDocument.lastOpenedAt, order: .reverse) private var documents: [LibraryDocument]

    @State private var isRightPanelVisible = false
    @State private var pdfDocument: PDFDocument?
    @State private var activeDocument: LibraryDocument?
    @State private var didRestoreLastDocument = false

    private let sidebarWidth: CGFloat = 220

    var body: some View {
        ZStack(alignment: .leading) {
            // Sidebar underneath
            SidebarView(
                onNewReading: { clearActiveDocument() },
                onOpenDocument: { openDocument($0) },
                onDeleteDocument: { deleteDocument($0) },
                documents: documents
            )
                .frame(maxHeight: .infinity)

            // Background fill for the rounded corner gaps (matches sidebar color)
            Color.white.opacity(0.55)
                .padding(.leading, sidebarWidth)

            // Main content area with optional right panel
            HStack(spacing: 0) {
                ReaderCanvasView(
                    isRightPanelVisible: $isRightPanelVisible,
                    activeDocument: $activeDocument,
                    pdfDocument: $pdfDocument
                )
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 12,
                        bottomLeadingRadius: 12,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.1), radius: 6, x: -2, y: 0)
                )

                if isRightPanelVisible {
                    RightPanelView()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.leading, sidebarWidth)
        }
        .ignoresSafeArea()
        .background(.ultraThinMaterial)
        .task {
            restoreLastDocumentIfNeeded()
        }
    }

    private func restoreLastDocumentIfNeeded() {
        guard didRestoreLastDocument == false else { return }
        didRestoreLastDocument = true

        guard activeDocument == nil, pdfDocument == nil else { return }
        guard let mostRecent = documents.first else { return }
        openDocument(mostRecent)
    }

    private func openDocument(_ document: LibraryDocument) {
        do {
            let url = try LibraryStore.fileURL(for: document)
            activeDocument = document
            pdfDocument = PDFDocument(url: url)
            document.lastOpenedAt = Date()
            try modelContext.save()
        } catch {
            print("Failed to open document: \(error)")
        }
    }

    private func clearActiveDocument() {
        activeDocument = nil
        pdfDocument = nil
    }

    private func deleteDocument(_ document: LibraryDocument) {
        if activeDocument?.id == document.id {
            clearActiveDocument()
        }

        do {
            try LibraryStore.deleteDocument(document, modelContext: modelContext)
        } catch {
            print("Failed to delete document: \(error)")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [LibraryDocument.self, Annotation.self], inMemory: true)
        .frame(width: 1200, height: 760)
}
