//
//  SidebarView.swift
//  verso-reads
//

import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DocumentCollection.createdAt, order: .forward) private var collections: [DocumentCollection]

    let onNewReading: () -> Void
    let onOpenDocument: (LibraryDocument) -> Void
    let onDeleteDocument: (LibraryDocument) -> Void
    let onSelectSettings: () -> Void
    let documents: [LibraryDocument]
    let activeDocumentID: UUID?

    @State private var isReadingExpanded = true
    @State private var isCreatingCollection = false
    @State private var newCollectionName = ""
    @FocusState private var isNewCollectionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                SidebarRow(icon: "plus", label: "New", action: onNewReading)
                SidebarRow(icon: "book", label: "Reading", action: { isReadingExpanded.toggle() })

                if isReadingExpanded {
                    if documents.isEmpty {
                        Text("No documents yet")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.black.opacity(0.35))
                            .padding(.vertical, 6)
                            .padding(.leading, 28)
                    } else {
                        ForEach(documents.prefix(8), id: \.id) { document in
                            LibraryDocumentRow(
                                documentID: document.id,
                                title: document.title,
                                isActive: document.id == activeDocumentID,
                                onOpen: { onOpenDocument(document) },
                                onDelete: { onDeleteDocument(document) }
                            )
                            .padding(.leading, 8)
                        }
                    }
                }

                SidebarRow(icon: "highlighter", label: "Highlights")
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Collections")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.4))

                    Spacer()

                    Button {
                        isCreatingCollection = true
                        newCollectionName = ""
                        isNewCollectionFocused = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)

                ForEach(collections) { collection in
                    DocumentCollectionRow(
                        collection: collection,
                        onDelete: { deleteCollection(collection) },
                        onDocumentDropped: { documentID in
                            addDocumentToCollection(documentID: documentID, collection: collection)
                        }
                    )
                }

                if isCreatingCollection {
                    HStack(spacing: 10) {
                        Image(systemName: "folder")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.black.opacity(0.5))
                            .frame(width: 20)

                        TextField("Collection name", text: $newCollectionName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .focused($isNewCollectionFocused)
                            .onSubmit {
                                createCollection()
                            }
                            .onExitCommand {
                                isCreatingCollection = false
                                newCollectionName = ""
                            }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }

                if collections.isEmpty && !isCreatingCollection {
                    Text("No collections yet")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.black.opacity(0.35))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                }
            }

            Spacer()

            SidebarRow(icon: "gearshape", label: "Settings", action: onSelectSettings)
                .foregroundStyle(Color.black.opacity(0.5))
        }
        .padding(.top, 52)
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .frame(width: 220, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white.opacity(0.55))
    }

    private func createCollection() {
        let trimmed = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            isCreatingCollection = false
            return
        }

        let collection = DocumentCollection(name: trimmed)
        modelContext.insert(collection)

        do {
            try modelContext.save()
        } catch {
            print("Failed to create collection: \(error)")
        }

        isCreatingCollection = false
        newCollectionName = ""
    }

    private func deleteCollection(_ collection: DocumentCollection) {
        modelContext.delete(collection)

        do {
            try modelContext.save()
        } catch {
            print("Failed to delete collection: \(error)")
        }
    }

    private func addDocumentToCollection(documentID: UUID, collection: DocumentCollection) {
        collection.addDocument(documentID)

        do {
            try modelContext.save()
        } catch {
            print("Failed to add document to collection: \(error)")
        }
    }
}

#Preview {
    SidebarView(
        onNewReading: {},
        onOpenDocument: { _ in },
        onDeleteDocument: { _ in },
        onSelectSettings: {},
        documents: [],
        activeDocumentID: nil
    )
        .frame(height: 600)
        .background(.ultraThinMaterial)
}
