//
//  NotepadView.swift
//  verso-reads
//

import SwiftUI
import SwiftData

struct NotepadView: View {
    @Binding var activeDocument: LibraryDocument?
    @Environment(\.modelContext) private var modelContext

    @State private var markdown: String = ""
    @State private var note: DocumentNote?
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        NotesWebView(markdown: markdown, onMarkdownChange: handleMarkdownChange)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                loadNote()
            }
            .onChange(of: activeDocument?.id) { _, _ in
                loadNote()
            }
    }

    private func loadNote() {
        saveTask?.cancel()

        guard let documentID = activeDocument?.id else {
            note = nil
            markdown = ""
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
                markdown = existing.markdown
            } else {
                note = nil
                markdown = ""
            }
        } catch {
            print("Failed to load note: \(error)")
            note = nil
            markdown = ""
        }
    }

    private func handleMarkdownChange(_ newMarkdown: String) {
        guard newMarkdown != markdown else { return }
        markdown = newMarkdown
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = markdown
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            saveMarkdown(snapshot)
        }
    }

    private func saveMarkdown(_ text: String) {
        guard let documentID = activeDocument?.id else { return }

        if note == nil {
            let newNote = DocumentNote(documentID: documentID, markdown: text)
            modelContext.insert(newNote)
            note = newNote
        } else {
            note?.markdown = text
            note?.updatedAt = Date()
        }

        do {
            try modelContext.save()
        } catch {
            print("Failed to save note: \(error)")
        }
    }
}

#Preview {
    NotepadView(activeDocument: .constant(nil))
        .frame(width: 340, height: 300)
        .background(Color(nsColor: .windowBackgroundColor))
}
