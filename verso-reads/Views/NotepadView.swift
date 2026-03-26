//
//  NotepadView.swift
//  verso-reads
//

import SwiftUI
import SwiftData
import Combine

struct NotepadView: View {
    @EnvironmentObject private var readerSession: ReaderSession
    @Environment(\.modelContext) private var modelContext

    @State private var content: String = ""
    @State private var note: DocumentNote?
    @State private var saveTask: Task<Void, Never>?
    @State private var pendingQuoteInsertion: QuoteInsertion?

    var body: some View {
        NotesWebView(
            content: content,
            documentID: readerSession.activeDocumentID,
            pendingQuoteInsertion: pendingQuoteInsertion,
            onContentChange: handleContentChange,
            onQuoteClick: handleQuoteClick,
            onQuoteRemove: handleQuoteRemove,
            onQuoteInserted: { pendingQuoteInsertion = nil }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadNote()
            // Check for pending note quote that was set before view mounted
            if let pending = readerSession.pendingNoteQuote {
                // Delay slightly to ensure WebView is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    handlePendingNoteQuote(pending)
                }
            }
        }
        .task(id: readerSession.activeDocumentID) {
            loadNote()
        }
        .onChange(of: readerSession.isRightPanelVisible) { _, isVisible in
            if isVisible {
                loadNote()
                // Check for pending note quote when panel opens
                if let pending = readerSession.pendingNoteQuote {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        handlePendingNoteQuote(pending)
                    }
                }
            }
        }
        .onChange(of: readerSession.pendingNoteQuote) { _, newValue in
            handlePendingNoteQuote(newValue)
        }
    }

    private func loadNote() {
        saveTask?.cancel()

        guard let documentID = readerSession.activeDocumentID else {
            print("[NotepadView] loadNote: no activeDocumentID")
            note = nil
            content = ""
            return
        }

        do {
            let predicate = #Predicate<DocumentNote> { note in
                note.documentID == documentID
            }
            var descriptor = FetchDescriptor<DocumentNote>(predicate: predicate)
            descriptor.fetchLimit = 1
            let results = try modelContext.fetch(descriptor)
            if let existing = results.first {
                note = existing
                content = existing.content
                print("[NotepadView] loadNote: found, length=\(existing.content.count)")
            } else {
                print("[NotepadView] loadNote: not found for \(documentID)")
                note = nil
                content = ""
            }
        } catch {
            print("[NotepadView] loadNote error: \(error)")
            note = nil
            content = ""
        }
    }

    private func handleContentChange(_ newContent: String) {
        guard newContent != content else { return }
        print("[NotepadView] contentChange: \(newContent.prefix(50))...")
        content = newContent
        // Save immediately - the view can be destroyed when sidebar closes
        saveContent(newContent)
    }

    private func handleQuoteClick(_ annotationId: UUID) {
        readerSession.noteQuoteNavigation.send(annotationId)
    }

    private func handleQuoteRemove(_ annotationId: UUID) {
        do {
            let predicate = #Predicate<Annotation> { annotation in
                annotation.id == annotationId
            }
            var descriptor = FetchDescriptor<Annotation>(predicate: predicate)
            descriptor.fetchLimit = 1
            guard let annotation = try modelContext.fetch(descriptor).first else { return }

            // Clear the highlight if this quote was active
            if readerSession.activeNoteQuoteAnchor == annotation.anchorData {
                readerSession.activeNoteQuoteAnchor = nil
            }

            modelContext.delete(annotation)
            try modelContext.save()
            print("[NotepadView] removed note quote: \(annotationId)")
        } catch {
            print("[NotepadView] failed to remove note quote: \(error)")
        }
    }

    private func handlePendingNoteQuote(_ insertion: NoteQuoteInsertion?) {
        guard let insertion else { return }
        guard readerSession.activeDocumentID == insertion.documentID else { return }

        let trimmed = insertion.quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        pendingQuoteInsertion = QuoteInsertion(
            quote: trimmed,
            annotationId: insertion.annotationID
        )

        DispatchQueue.main.async {
            if readerSession.pendingNoteQuote?.annotationID == insertion.annotationID {
                readerSession.pendingNoteQuote = nil
            }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = content
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            saveContent(snapshot)
        }
    }

    private func saveContent(_ text: String) {
        guard let documentID = readerSession.activeDocumentID else { return }

        if note == nil {
            let newNote = DocumentNote(documentID: documentID, content: text)
            modelContext.insert(newNote)
            note = newNote
            print("[NotepadView] created new note")
        } else {
            note?.content = text
            note?.updatedAt = Date()
            print("[NotepadView] updated existing note")
        }

        do {
            try modelContext.save()
            print("[NotepadView] saved OK, length=\(text.count)")
        } catch {
            print("[NotepadView] save FAILED: \(error)")
        }
    }
}

#Preview {
    NotepadView()
        .frame(width: 340, height: 300)
        .background(Color(nsColor: .windowBackgroundColor))
        .environmentObject(ReaderSession())
}
