//
//  DocumentCollectionRow.swift
//  verso-reads
//

import SwiftUI

struct DocumentCollectionRow: View {
    let collection: DocumentCollection
    let onDelete: () -> Void
    let onDocumentDropped: (UUID) -> Void

    @State private var isHovering = false
    @State private var isTargeted = false
    @State private var isConfirmingDelete = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 14))
                .frame(width: 20)

            Text(collection.name)
                .font(.system(size: 13, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if isHovering {
                if isConfirmingDelete {
                    Button {
                        isConfirmingDelete = false
                        onDelete()
                    } label: {
                        Text("Confirm")
                            .font(.system(size: 11, weight: .light))
                            .foregroundStyle(Color.red.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        isConfirmingDelete = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.black.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .foregroundStyle(Color.black.opacity(0.65))
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering == false {
                isConfirmingDelete = false
            }
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
            onDelete: {},
            onDocumentDropped: { _ in }
        )
        DocumentCollectionRow(
            collection: {
                let c = DocumentCollection(name: "Research Papers")
                return c
            }(),
            onDelete: {},
            onDocumentDropped: { _ in }
        )
    }
    .padding()
    .frame(width: 220)
}
