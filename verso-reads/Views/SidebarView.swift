//
//  SidebarView.swift
//  verso-reads
//

import SwiftUI

struct SidebarView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                SidebarRow(icon: "books.vertical", label: "Library")
                SidebarRow(icon: "book", label: "Reading")
                SidebarRow(icon: "highlighter", label: "Highlights")
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

            SidebarRow(icon: "gearshape", label: "Settings")
                .foregroundStyle(Color.black.opacity(0.5))
        }
        .padding(.top, 52)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(width: 220, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white.opacity(0.55))
    }
}

#Preview {
    SidebarView()
        .frame(height: 600)
        .background(.ultraThinMaterial)
}
