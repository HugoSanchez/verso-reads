//
//  RightPanelView.swift
//  verso-reads
//

import SwiftUI

struct RightPanelView: View {
    @Binding var chatContext: ChatContext?
    @Binding var messages: [ChatMessage]
    @ObservedObject var settings: OpenAISettingsStore

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
                ChatView(context: $chatContext, messages: $messages, settings: settings)
            }
        }
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    HStack(spacing: 0) {
        Color.gray.opacity(0.1)
        RightPanelView(chatContext: .constant(nil), messages: .constant([]), settings: OpenAISettingsStore())
    }
    .frame(width: 800, height: 600)
}
