//
//  SidebarRow.swift
//  verso-reads
//

import SwiftUI

struct SidebarRow: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 20)
            Text(label)
                .font(.system(size: 13, weight: .regular))
        }
        .foregroundStyle(Color.black.opacity(0.75))
        .padding(.vertical, 4)
    }
}

#Preview {
    VStack(alignment: .leading) {
        SidebarRow(icon: "books.vertical", label: "Library")
        SidebarRow(icon: "book", label: "Reading")
    }
    .padding()
}
