//
//  ChatView.swift
//  verso-reads
//

import SwiftUI

struct ChatView: View {
    @Binding var context: ChatContext?
    @Binding var messages: [ChatMessage]
    @ObservedObject var settings: OpenAISettingsStore

    @State private var inputText: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?

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
        Group {
            if messages.isEmpty {
                VStack {
                    Spacer()
                    Text("No chats yet")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.black.opacity(0.4))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { message in
                            chatBubble(for: message)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var chatInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let context {
                HStack(spacing: 8) {
                    Text("\(context.wordCount) words selected")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.7))
                    Spacer()
                    Button(action: { self.context = nil }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.06))
                )
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask about the text...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...5)

                Button(action: sendMessage) {
                    Image(systemName: "paperplane")
                        .font(.system(size: 14))
                        .foregroundStyle(sendButtonColor)
                }
                .buttonStyle(.plain)
                .disabled(canSend == false)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red.opacity(0.7))
            } else if settings.hasAPIKey == false {
                Text("Add your OpenAI API key in Settings to enable chat.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.black.opacity(0.45))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.05))
        )
        .padding(16)
    }

    private func chatBubble(for message: ChatMessage) -> some View {
        HStack {
            if message.role == .assistant {
                bubbleText(message.content, alignment: .leading, background: Color.black.opacity(0.04))
                Spacer(minLength: 20)
            } else {
                Spacer(minLength: 20)
                bubbleText(message.content, alignment: .trailing, background: Color.accentColor.opacity(0.12))
            }
        }
    }

    private func bubbleText(_ text: String, alignment: HorizontalAlignment, background: Color) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(background)
            )
            .frame(maxWidth: 240, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        guard settings.hasAPIKey else { return }

        errorMessage = nil

        let assistantID = UUID()
        messages.append(ChatMessage(role: .user, content: trimmed))
        messages.append(ChatMessage(id: assistantID, role: .assistant, content: ""))
        inputText = ""

        let contextText = context?.text
        let prompt = buildPrompt(question: trimmed, context: contextText)
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = OpenAIClient(apiKey: apiKey, model: model.isEmpty ? "gpt-5.2" : model)

        isSending = true

        Task {
            do {
                for try await delta in client.streamResponse(systemPrompt: systemPrompt, userPrompt: prompt) {
                    await MainActor.run {
                        appendDelta(delta, to: assistantID)
                    }
                }
                await MainActor.run {
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private var canSend: Bool {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty == false && isSending == false && settings.hasAPIKey
    }

    private var sendButtonColor: Color {
        if canSend {
            return Color.accentColor
        }
        return Color.black.opacity(0.3)
    }

    private var systemPrompt: String {
        "You are a helpful reading assistant. Be concise and reference the provided text when possible."
    }

    private func buildPrompt(question: String, context: String?) -> String {
        if let context, context.isEmpty == false {
            return "Context:\n\(context)\n\nQuestion:\n\(question)"
        }
        return question
    }

    private func appendDelta(_ delta: String, to assistantID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }
        messages[index].content += delta
    }
}

#Preview {
    ChatView(context: .constant(nil), messages: .constant([]), settings: OpenAISettingsStore())
        .frame(width: 340, height: 300)
        .background(Color(nsColor: .windowBackgroundColor))
}
