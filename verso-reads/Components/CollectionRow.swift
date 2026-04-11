//
//  DocumentCollectionRow.swift
//  verso-reads
//

import SwiftUI

struct DocumentCollectionRow: View {
    let collection: DocumentCollection
    let isExpanded: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    let onDocumentDropped: (UUID) -> Void

    @State private var isHovering = false
    @State private var isTargeted = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.3))
                .frame(width: 16)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.15), value: isExpanded)

            Text(collection.name)
                .font(.system(size: 13, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)
        }
        .foregroundStyle(Color.black.opacity(0.65))
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button("Delete Collection") {
                showDeleteConfirmation = true
            }
        }
        .alert("Delete Collection", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This will delete the collection \"\(collection.name)\" and remove all its contents. Are you sure?")
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(backgroundColor)
        )
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first, let uuid = UUID(uuidString: first) else { return false }
            onDocumentDropped(uuid)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .animation(.easeInOut(duration: 0.12), value: isTargeted)
    }

    private var backgroundColor: Color {
        if isTargeted {
            return Color.accentColor.opacity(0.15)
        } else if isHovering {
            return Color.black.opacity(0.035)
        } else {
            return Color.clear
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 6) {
        DocumentCollectionRow(
            collection: {
                let c = DocumentCollection(name: "Work")
                return c
            }(),
            isExpanded: false,
            onTap: {},
            onDelete: {},
            onDocumentDropped: { _ in }
        )
        DocumentCollectionRow(
            collection: {
                let c = DocumentCollection(name: "Research Papers")
                return c
            }(),
            isExpanded: true,
            onTap: {},
            onDelete: {},
            onDocumentDropped: { _ in }
        )
    }
    .padding()
    .frame(width: 240)
}
