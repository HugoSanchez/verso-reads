//
//  ContentView.swift
//  verso-reads
//
//  Created by Hugo Sanchez on 12/2/26.
//

import SwiftUI
import PDFKit
import SwiftData

private enum MainPanel {
    case reader
    case settings
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LibraryDocument.lastOpenedAt, order: .reverse) private var documents: [LibraryDocument]

    @State private var isRightPanelVisible = false
    @State private var pdfDocument: PDFDocument?
    @State private var activeDocument: LibraryDocument?
    @State private var didRestoreLastDocument = false
    @State private var chatContext: ChatContext?
    @State private var chatMessages: [ChatMessage] = []
    @StateObject private var selectionDismiss = SelectionDismissController()
    @StateObject private var openAISettings = OpenAISettingsStore()
    @State private var mainPanel: MainPanel = .reader

    private let sidebarWidth: CGFloat = 220

    var body: some View {
        ZStack(alignment: .leading) {
            // Sidebar underneath
            SidebarView(
                onNewReading: { clearActiveDocument() },
                onOpenDocument: { openDocument($0) },
                onDeleteDocument: { deleteDocument($0) },
                onSelectSettings: { showSettings() },
                documents: documents
            )
                .frame(maxHeight: .infinity)

            // Background fill for the rounded corner gaps (matches sidebar color)
            Color.white.opacity(0.55)
                .padding(.leading, sidebarWidth)

            // Main content area with optional right panel
            HStack(spacing: 0) {
                mainPanelView
            }
            .padding(.leading, sidebarWidth)
        }
        .ignoresSafeArea()
        .background(.ultraThinMaterial)
        .simultaneousGesture(
            TapGesture().onEnded {
                if selectionDismiss.isActive {
                    selectionDismiss.clearIfPossible()
                }
            }
        )
        .task {
            restoreLastDocumentIfNeeded()
            openAISettings.load()
        }
    }

    @ViewBuilder
    private var mainPanelView: some View {
        if mainPanel == .settings {
            SettingsView(settings: openAISettings)
                .background(readerBackground)
        } else {
            ReaderCanvasView(
                isRightPanelVisible: $isRightPanelVisible,
                activeDocument: $activeDocument,
                pdfDocument: $pdfDocument,
                onAddSelectionToChat: addSelectionToChat,
                selectionDismiss: selectionDismiss
            )
            .background(readerBackground)

            if isRightPanelVisible {
                RightPanelView(
                    chatContext: $chatContext,
                    messages: $chatMessages,
                    settings: openAISettings
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private var readerBackground: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 12,
            bottomLeadingRadius: 12,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0
        )
        .fill(Color.white)
        .shadow(color: Color.black.opacity(0.1), radius: 6, x: -2, y: 0)
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
            chatContext = nil
            chatMessages = []
            mainPanel = .reader
        } catch {
            print("Failed to open document: \(error)")
        }
    }

    private func clearActiveDocument() {
        activeDocument = nil
        pdfDocument = nil
        chatContext = nil
        chatMessages = []
        mainPanel = .reader
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

    private func addSelectionToChat(_ context: ChatContext) {
        chatContext = context
        isRightPanelVisible = true
        mainPanel = .reader
    }

    private func showSettings() {
        mainPanel = .settings
        isRightPanelVisible = false
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [LibraryDocument.self, Annotation.self], inMemory: true)
        .frame(width: 1200, height: 760)
}
