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
    @State private var inputHeight: CGFloat = 22
    @State private var isInputFocused = false
    
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
                ZStack(alignment: .leading) {
                    if inputText.isEmpty && isInputFocused == false {
                        Text("Ask about the text...")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.black.opacity(0.4))
                            .padding(.leading, 4)
                    }

                    AutoGrowingTextView(
                        text: $inputText,
                        height: $inputHeight,
                        isFocused: $isInputFocused,
                        fontSize: 13,
                        maxLines: 3,
                        onSubmit: {
                            if canSend {
                                sendMessage()
                            }
                        }
                    )
                    .frame(height: inputHeight)
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
        inputHeight = 22
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

private struct AutoGrowingTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    @Binding var isFocused: Bool
    let fontSize: CGFloat
    let maxLines: Int
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            height: $height,
            isFocused: $isFocused,
            fontSize: fontSize,
            maxLines: maxLines,
            onSubmit: onSubmit
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.backgroundColor = .clear
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textColor = NSColor.black.withAlphaComponent(0.85)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.updateHeight()

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textDidBeginEditing),
            name: NSText.didBeginEditingNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textDidEndEditing),
            name: NSText.didEndEditingNotification,
            object: textView
        )

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.updateHeight()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var height: CGFloat
        @Binding var isFocused: Bool
        let fontSize: CGFloat
        let maxLines: Int
        weak var textView: NSTextView?

        let onSubmit: () -> Void

        init(
            text: Binding<String>,
            height: Binding<CGFloat>,
            isFocused: Binding<Bool>,
            fontSize: CGFloat,
            maxLines: Int,
            onSubmit: @escaping () -> Void
        ) {
            _text = text
            _height = height
            _isFocused = isFocused
            self.fontSize = fontSize
            self.maxLines = maxLines
            self.onSubmit = onSubmit
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            updateHeight()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    return false
                }
                onSubmit()
                return true
            }
            return false
        }

        @objc func textDidBeginEditing() {
            isFocused = true
        }

        @objc func textDidEndEditing() {
            isFocused = false
        }

        func updateHeight() {
            guard let textView else { return }
            guard let textContainer = textView.textContainer else { return }
            textView.layoutManager?.ensureLayout(for: textContainer)
            let usedRect = textView.layoutManager?.usedRect(for: textContainer) ?? .zero
            let font = NSFont.systemFont(ofSize: fontSize)
            let lineHeight = font.ascender - font.descender + font.leading
            let maxHeight = lineHeight * CGFloat(maxLines) + (textView.textContainerInset.height * 2)
            let targetHeight = max(lineHeight, min(usedRect.height + (textView.textContainerInset.height * 2), maxHeight))
            if abs(height - targetHeight) > 0.5 {
                height = targetHeight
            }
        }
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
