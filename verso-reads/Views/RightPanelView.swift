//
//  RightPanelView.swift
//  verso-reads
//

import SwiftUI

struct RightPanelView: View {
    @State private var inputText: String = ""

    var body: some View {
        HStack(spacing: 0) {
            // Vertical divider
            Divider()

            // Panel content
            VStack(spacing: 0) {
                // Top section (future notepad)
                notesSection

                Divider()

                // Bottom section (chat)
                chatSection
            }
        }
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var notesSection: some View {
        VStack {
            Spacer()
            Text("No notes yet")
                .font(.system(size: 13))
                .foregroundStyle(Color.black.opacity(0.4))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatSection: some View {
        VStack(spacing: 0) {
            // Chat content area
            VStack {
                Spacer()
                Text("No chats yet")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black.opacity(0.4))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Input area
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask about the text...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...5)

                Button(action: {}) {
                    Image(systemName: "paperplane")
                        .font(.system(size: 14))
                        .foregroundStyle(inputText.isEmpty ? Color.black.opacity(0.3) : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.05))
            )
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    HStack(spacing: 0) {
        Color.gray.opacity(0.1)
        RightPanelView()
    }
    .frame(width: 800, height: 600)
}
