//
//  ChatView.swift
//  verso-reads
//

import SwiftUI

struct ChatView: View {
    @State private var inputText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Chat content area
            chatContent

            // Input area
            chatInput
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatContent: some View {
        VStack {
            Spacer()
            Text("No chats yet")
                .font(.system(size: 13))
                .foregroundStyle(Color.black.opacity(0.4))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatInput: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask about the text...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...5)

            Button(action: sendMessage) {
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

    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        // TODO: Implement send message functionality
        inputText = ""
    }
}

#Preview {
    ChatView()
        .frame(width: 340, height: 300)
        .background(Color(nsColor: .windowBackgroundColor))
}
