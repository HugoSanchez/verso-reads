//
//  SidebarRow.swift
//  verso-reads
//

import SwiftUI

struct SidebarRow: View {
    let icon: String
    let label: String
    var action: (() -> Void)? = nil
    @State private var isHovering = false

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovering ? Color.black.opacity(0.035) : Color.clear)
        )
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 20)
            Text(label)
                .font(.system(size: 13, weight: .regular))
        }
        .foregroundStyle(Color.black.opacity(0.75))
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    VStack(alignment: .leading) {
        SidebarRow(icon: "books.vertical", label: "Library")
        SidebarRow(icon: "book", label: "Reading")
    }
    .padding()
}
