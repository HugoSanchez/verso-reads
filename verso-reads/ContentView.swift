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
    @State private var pinnedPreview: PinnedChatPreview?
    @State private var isPinHighlightVisible: Bool = true
    @StateObject private var selectionDismiss = SelectionDismissController()
    @StateObject private var openAISettings = OpenAISettingsStore()
    @State private var mainPanel: MainPanel = .reader
    @State private var isSidebarVisible: Bool = true
    @StateObject private var readerSession = ReaderSession()

    private let sidebarWidth: CGFloat = 220
    private var sidebarInset: CGFloat { isSidebarVisible ? sidebarWidth : 0 }

    var body: some View {
        ZStack(alignment: .leading) {
            // Sidebar underneath
            SidebarView(
                onNewReading: { clearActiveDocument() },
                onOpenDocument: { openDocument($0) },
                onDeleteDocument: { deleteDocument($0) },
                onSelectSettings: { showSettings() },
                documents: documents,
                activeDocumentID: activeDocument?.id
            )
            .frame(maxHeight: .infinity)
            .offset(x: isSidebarVisible ? 0 : -(sidebarWidth + 24))
            .opacity(isSidebarVisible ? 1 : 0)
            .allowsHitTesting(isSidebarVisible)

            // Background fill for the rounded corner gaps (matches sidebar color)
            Color.white.opacity(0.55)
                .padding(.leading, sidebarInset)
                .opacity(isSidebarVisible ? 1 : 0)
                .allowsHitTesting(false)

            // Main content area with optional right panel
            HStack(spacing: 0) {
                mainPanelView
            }
            .padding(.leading, sidebarInset)
        }
        .ignoresSafeArea()
        .background(.ultraThinMaterial)
        .environmentObject(readerSession)
        .simultaneousGesture(
            TapGesture().onEnded {
                if selectionDismiss.isActive {
                    selectionDismiss.clearIfPossible()
                }
            }
        )
        .onChange(of: isRightPanelVisible) { _, isVisible in
            readerSession.isRightPanelVisible = isVisible
        }
        .task {
            restoreLastDocumentIfNeeded()
            openAISettings.load()
            readerSession.isRightPanelVisible = isRightPanelVisible
        }
    }

    @ViewBuilder
    private var mainPanelView: some View {
        if mainPanel == .settings {
            SettingsView(settings: openAISettings)
                .background(readerBackground)
        } else {
            ReaderCanvasView(
                isSidebarVisible: $isSidebarVisible,
                isRightPanelVisible: $isRightPanelVisible,
                activeDocument: $activeDocument,
                pdfDocument: $pdfDocument,
                activePinAnchor: activePinAnchorBinding,
                onAddSelectionToChat: addSelectionToChat,
                onShowPinnedAnswer: showPinnedAnswer,
                onTogglePinHighlight: togglePinHighlight,
                onClearPinHighlight: clearPinHighlight,
                selectionDismiss: selectionDismiss
            )
            .background(readerBackground)

            if isRightPanelVisible {
                RightPanelView(
                    chatContext: $chatContext,
                    messages: $chatMessages,
                    settings: openAISettings,
                    pinnedPreview: $pinnedPreview,
                    activeDocument: $activeDocument,
                    isRightPanelVisible: $isRightPanelVisible,
                    isSidebarVisible: isSidebarVisible
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
            readerSession.activeDocumentID = document.id
            pdfDocument = PDFDocument(url: url)
            document.lastOpenedAt = Date()
            try modelContext.save()
            chatContext = nil
            chatMessages = []
            mainPanel = .reader
            Task {
                await RAGIngestionManager.shared.ensureIndexed(document: document, fileURL: url)
            }
        } catch {
            print("Failed to open document: \(error)")
        }
    }

    private func clearActiveDocument() {
        activeDocument = nil
        readerSession.activeDocumentID = nil
        pdfDocument = nil
        chatContext = nil
        chatMessages = []
        pinnedPreview = nil
        isRightPanelVisible = false
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
#if DEBUG
        print("[Chat] selection added to chat anchor=\(context.anchorData != nil) wordCount=\(context.wordCount)")
#endif
        isRightPanelVisible = true
        mainPanel = .reader
    }

    private func showPinnedAnswer(_ annotation: Annotation) {
        guard annotation.kind == .chatPin else { return }
        guard let assistantID = annotation.chatMessageID else { return }

        let assistantText = fetchChatMessage(id: assistantID)?.content ?? annotation.body ?? ""
        let userText: String?
        if let promptID = annotation.chatPromptID,
           let promptRecord = fetchChatMessage(id: promptID) {
            userText = promptRecord.content
        } else {
            userText = annotation.chatPromptSnapshot
        }

        pinnedPreview = PinnedChatPreview(
            id: annotation.id,
            assistantMessageID: assistantID,
            assistantText: assistantText,
            userText: userText,
            anchorData: annotation.anchorData
        )
        isPinHighlightVisible = true
        isRightPanelVisible = true
        mainPanel = .reader
    }

    private func fetchChatMessage(id: UUID) -> ChatMessageRecord? {
        let predicate = #Predicate<ChatMessageRecord> { record in
            record.id == id
        }
        let descriptor = FetchDescriptor<ChatMessageRecord>(predicate: predicate)
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            print("Failed to fetch chat message: \(error)")
            return nil
        }
    }

    private var activePinAnchorBinding: Binding<Data?> {
        Binding(
            get: { isPinHighlightVisible ? pinnedPreview?.anchorData : nil },
            set: { _ in }
        )
    }

    private func togglePinHighlight() {
        isPinHighlightVisible.toggle()
    }

    private func clearPinHighlight() {
        isPinHighlightVisible = false
    }

    private func showSettings() {
        mainPanel = .settings
        isRightPanelVisible = false
    }

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSidebarVisible.toggle()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [LibraryDocument.self, Annotation.self, DocumentNote.self, ChatMessageRecord.self], inMemory: true)
        .frame(width: 1200, height: 760)
}
