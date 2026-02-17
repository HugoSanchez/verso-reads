//
//  RightPanelView.swift
//  verso-reads
//

import SwiftUI

struct RightPanelView: View {
    var body: some View {
        HStack(spacing: 0) {
            // Vertical divider
            Divider()

            // Panel content
            VStack(spacing: 0) {
                // Top section (notepad)
                NotepadView()

                Divider()

                // Bottom section (chat)
                ChatView()
            }
        }
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    HStack(spacing: 0) {
        Color.gray.opacity(0.1)
        RightPanelView()
    }
    .frame(width: 800, height: 600)
}
