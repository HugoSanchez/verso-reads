//
//  ChatView.swift
//  verso-reads
//

import SwiftUI
import AppKit
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var context: ChatContext?
    @Binding var messages: [ChatMessage]
    @ObservedObject var settings: OpenAISettingsStore
    @Binding var activeDocument: LibraryDocument?

    @State private var inputText: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var renderedText: [UUID: NSAttributedString] = [:]
    @State private var pendingRenders: Set<UUID> = []
    @State private var lastRenderAt: [UUID: Date] = [:]
    
    private let renderInterval: TimeInterval = 0.02
    private let messageFontSize: CGFloat = 12
    private let historyLimit: Int = 12

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
                .scrollIndicators(.hidden)
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
                TextField("Ask about the text...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit {
                        if canSend {
                            sendMessage()
                        }
                    }

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

    @ViewBuilder
    private func chatBubble(for message: ChatMessage) -> some View {
            if message.role == .assistant,
               message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyView()
        } else {
            HStack {
                if message.role == .assistant {
                    bubbleText(
                        renderedContent(for: message),
                        messageID: message.id,
                        alignment: .leading,
                        background: Color.clear,
                        maxWidth: .infinity
                    )
                    Spacer(minLength: 20)
                } else {
                    Spacer(minLength: 20)
                    userBubbleText(message.content)
                }
            }
        }
    }

    private func bubbleText(
        _ text: NSAttributedString,
        messageID: UUID,
        alignment: HorizontalAlignment,
        background: Color,
        maxWidth: CGFloat
    ) -> some View {
        MarkdownTextView(text: text)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(background)
        )
        .frame(maxWidth: maxWidth, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func userBubbleText(_ text: String) -> some View {
        ViewThatFits(in: .horizontal) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color.black.opacity(0.85))
                .textSelection(.enabled)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color.black.opacity(0.85))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
        )
        .frame(maxWidth: 240, alignment: .trailing)
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        guard settings.hasAPIKey else { return }

        errorMessage = nil

        let historyMessages = messages
        let assistantID = UUID()
        let userMessage = ChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)
        messages.append(ChatMessage(id: assistantID, role: .assistant, content: ""))
        renderNow(for: userMessage.id)
        renderNow(for: assistantID)
        inputText = ""
        persistMessage(userMessage)

        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = OpenAIClient(apiKey: apiKey, model: model.isEmpty ? "gpt-5.2" : model)

        isSending = true

        Task {
            do {
                let contextText = await resolveContext(question: trimmed, apiKey: apiKey)
                let prompt = buildPrompt(question: trimmed, context: contextText)
                let conversation = buildConversationMessages(from: historyMessages, userPrompt: prompt)
                for try await delta in client.streamResponse(systemPrompt: systemPrompt, messages: conversation) {
                    await MainActor.run {
                        appendDelta(delta, to: assistantID)
                    }
                }
                await MainActor.run {
                    isSending = false
                    renderNow(for: assistantID)
                    persistAssistantMessageIfNeeded(id: assistantID)
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

    private func buildConversationMessages(from history: [ChatMessage], userPrompt: String) -> [OpenAIClient.Message] {
        let trimmedHistory = history
            .filter { $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            .suffix(historyLimit)
        let mapped = trimmedHistory.map { message -> OpenAIClient.Message in
            OpenAIClient.Message(
                role: message.role == .user ? "user" : "assistant",
                content: message.content
            )
        }
        return mapped + [OpenAIClient.Message(role: "user", content: userPrompt)]
    }

    private func resolveContext(question: String, apiKey: String) async -> String? {
        if let selectionText = context?.text, selectionText.isEmpty == false {
            return selectionText
        }

        guard let activeDocument else { return nil }
        guard apiKey.isEmpty == false else { return nil }

        do {
            return try await RAGQueryService.shared.retrieveContext(
                documentID: activeDocument.id,
                query: question,
                apiKey: apiKey
            )
        } catch {
            print("RAG context unavailable: \(error.localizedDescription)")
            return nil
        }
    }

    @MainActor
    private func persistMessage(_ message: ChatMessage) {
        guard let documentID = activeDocument?.id else { return }
        let record = ChatMessageRecord(
            id: message.id,
            documentID: documentID,
            role: message.role,
            content: message.content
        )
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            print("Failed to save chat message: \(error)")
        }
    }

    @MainActor
    private func persistAssistantMessageIfNeeded(id: UUID) {
        guard let documentID = activeDocument?.id else { return }
        guard let message = messages.first(where: { $0.id == id }) else { return }
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        let record = ChatMessageRecord(
            id: message.id,
            documentID: documentID,
            role: message.role,
            content: message.content
        )
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            print("Failed to save assistant message: \(error)")
        }
    }

    private func appendDelta(_ delta: String, to assistantID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }
        messages[index].content += delta
        scheduleRender(for: assistantID)
    }

    private func renderedContent(for message: ChatMessage) -> NSAttributedString {
        if let cached = renderedText[message.id] {
            return cached
        }
        return renderMarkdown(message.content)
    }

    private func renderNow(for messageID: UUID) {
        guard let message = messages.first(where: { $0.id == messageID }) else { return }
        renderedText[messageID] = renderMarkdown(message.content)
    }

    private func scheduleRender(for messageID: UUID) {
        let now = Date()
        let last = lastRenderAt[messageID] ?? .distantPast
        let elapsed = now.timeIntervalSince(last)

        if elapsed >= renderInterval, pendingRenders.contains(messageID) == false {
            lastRenderAt[messageID] = now
            renderNow(for: messageID)
            return
        }

        guard pendingRenders.contains(messageID) == false else { return }
        pendingRenders.insert(messageID)
        let delay = max(renderInterval - elapsed, 0.01)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            pendingRenders.remove(messageID)
            lastRenderAt[messageID] = Date()
            renderNow(for: messageID)
        }
    }

    private func renderMarkdown(_ text: String) -> NSAttributedString {
        MarkdownRenderer.renderAttributed(
            text,
            fontSize: messageFontSize,
            textColor: NSColor.black.withAlphaComponent(0.85)
        )
    }
}

#Preview {
    ChatView(
        context: .constant(nil),
        messages: .constant([]),
        settings: OpenAISettingsStore(),
        activeDocument: .constant(nil)
    )
        .frame(width: 340, height: 300)
        .background(Color(nsColor: .windowBackgroundColor))
}
