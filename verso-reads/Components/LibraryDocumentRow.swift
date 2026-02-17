//
//  LibraryDocumentRow.swift
//  verso-reads
//

import SwiftUI

struct LibraryDocumentRow: View {
    let title: String
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var isConfirmingDelete = false

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: openTapped) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 14))
                        .frame(width: 20)

                    Text(title)
                        .font(.system(size: 13, weight: .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    if isHovering {
                        Color.clear.frame(width: trailingReservationWidth, height: 1)
                    }
                }
                .foregroundStyle(Color.black.opacity(0.75))
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if isHovering {
                if isConfirmingDelete {
                    confirmButton
                        .padding(.trailing, 8)
                } else {
                    archiveButton
                        .padding(.trailing, 8)
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering == false {
                isConfirmingDelete = false
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovering ? Color.black.opacity(0.035) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .animation(.easeInOut(duration: 0.12), value: isConfirmingDelete)
    }

    private var trailingReservationWidth: CGFloat {
        isConfirmingDelete ? 64 : 28
    }

    private func openTapped() {
        if isConfirmingDelete {
            isConfirmingDelete = false
            return
        }
        onOpen()
    }

    private var archiveButton: some View {
        Button {
            isConfirmingDelete = true
        } label: {
            Image(systemName: "archivebox")
                .font(.system(size: 13))
                .foregroundStyle(Color.black.opacity(0.35))
                .frame(width: 28, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var confirmButton: some View {
        Button {
            isConfirmingDelete = false
            onDelete()
        } label: {
            Text("Confirm")
                .font(.system(size: 11, weight: .light))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(Color.red.opacity(0.75))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 6) {
        LibraryDocumentRow(title: "itsverso_ Inc. Certificate of Incorporation (1)", onOpen: {}, onDelete: {})
        LibraryDocumentRow(title: "Short title", onOpen: {}, onDelete: {})
    }
    .padding()
    .frame(width: 220)
}
