//
//  SidebarView.swift
//  verso-reads
//

import SwiftUI

struct SidebarView: View {
    let onNewReading: () -> Void
    let onOpenDocument: (LibraryDocument) -> Void
    let onDeleteDocument: (LibraryDocument) -> Void
    let onSelectSettings: () -> Void
    let documents: [LibraryDocument]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                SidebarRow(icon: "plus", label: "New", action: onNewReading)
                SidebarRow(icon: "book", label: "Reading")
                SidebarRow(icon: "highlighter", label: "Highlights")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Library")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.4))
                    .padding(.top, 8)

                if documents.isEmpty {
                    Text("No documents yet")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.black.opacity(0.35))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                } else {
                    ForEach(documents.prefix(8), id: \.id) { document in
                        LibraryDocumentRow(
                            title: document.title,
                            onOpen: { onOpenDocument(document) },
                            onDelete: { onDeleteDocument(document) }
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Collections")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.4))
                    .padding(.top, 8)

                SidebarRow(icon: "bookmark", label: "Classics")
                SidebarRow(icon: "brain.head.profile", label: "Philosophy")
                SidebarRow(icon: "magnifyingglass", label: "Notes to Revisit")
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
}

#Preview {
    SidebarView(
        onNewReading: {},
        onOpenDocument: { _ in },
        onDeleteDocument: { _ in },
        onSelectSettings: {},
        documents: []
    )
        .frame(height: 600)
        .background(.ultraThinMaterial)
}
