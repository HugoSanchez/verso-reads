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
    @Binding var pinnedPreview: PinnedChatPreview?
    @Binding var activeDocument: LibraryDocument?
    var showInput: Bool = true

    @State private var inputText: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var renderedText: [UUID: NSAttributedString] = [:]
    @State private var streamingMessageID: UUID?
    @State private var inputHeight: CGFloat = 22
    @State private var isInputFocused = false
    @State private var toolStatus: String?

    private let messageFontSize: CGFloat = 12
    private let historyLimit: Int = 50

    var body: some View {
        VStack(spacing: 0) {
            // Chat content area
            chatContent

            // Input area
            if showInput {
                chatInput
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatContent: some View {
        Group {
            if messages.isEmpty && pinnedPreview == nil {
                VStack {
                    Spacer()
                    Text("No chats yet")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.black.opacity(0.4))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let preview = pinnedPreview {
                                pinnedPreviewCard(preview)
                            }
                            ForEach(messages) { message in
                                chatBubble(for: message)
                                    .id(message.id)
                            }
                        }
                        .padding(16)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: pinnedPreview?.assistantMessageID) { _, newValue in
                        guard let targetID = newValue else { return }
                        guard messages.contains(where: { $0.id == targetID }) else { return }
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(targetID, anchor: .center)
                            }
                        }
                    }
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
                    VStack(alignment: .leading, spacing: 6) {
                        bubbleText(
                            renderedContent(for: message),
                            messageID: message.id,
                            alignment: .leading,
                            background: Color.clear,
                            maxWidth: .infinity
                        )
                        if let status = toolStatus, isSending, message.content.isEmpty || messages.last?.id == message.id {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(status)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.black.opacity(0.45))
                                    .italic()
                            }
                            .padding(.leading, 10)
                        }
                        if canPin(message) {
                            Button("Pin answer to text") {
                                pinAnswer(message)
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .buttonStyle(.plain)
                        }
                    }
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
        let selectionAnchor = context?.anchorData
        let selectionText = context?.text
#if DEBUG
        print("[Chat] sendMessage selectionAnchor=\(selectionAnchor != nil) selectionTextCount=\(selectionText?.count ?? 0)")
#endif
        let assistantID = UUID()
        let userMessage = ChatMessage(
            role: .user,
            content: trimmed,
            sourceAnchorData: selectionAnchor,
            sourceSelectionText: selectionText
        )
        messages.append(userMessage)
        messages.append(
            ChatMessage(
                id: assistantID,
                role: .assistant,
                content: "",
                sourceAnchorData: selectionAnchor,
                sourceSelectionText: selectionText,
                promptMessageID: userMessage.id
            )
        )
#if DEBUG
        print("[Chat] created assistantMessage id=\(assistantID) anchor=\(selectionAnchor != nil)")
#endif
        renderNow(for: userMessage.id)
        renderNow(for: assistantID)
        inputText = ""
        inputHeight = 22
        persistMessage(userMessage)

        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = OpenAIClient(apiKey: apiKey, model: model.isEmpty ? "gpt-5.2" : model)

        isSending = true
        toolStatus = nil

        Task {
            do {
                // Build the user prompt with selection context if available
                let userPrompt: String
                if let selectionText, selectionText.isEmpty == false {
                    userPrompt = "Selected text:\n\(selectionText)\n\nQuestion:\n\(trimmed)"
                } else {
                    userPrompt = trimmed
                }

                let conversation = buildConversationMessages(from: historyMessages, userPrompt: userPrompt)
                let documentTitle = activeDocument?.title ?? "Unknown Document"

                let executor = ToolExecutor(
                    documentID: activeDocument?.id ?? UUID(),
                    apiKey: apiKey,
                    modelContext: modelContext
                )

                let agentLoop = AgentLoop(
                    client: client,
                    systemPrompt: AgentLoop.buildSystemPrompt(documentTitle: documentTitle),
                    tools: AgentTools.all,
                    toolExecutor: executor
                )

                for try await event in agentLoop.run(messages: conversation) {
                    await MainActor.run {
                        switch event {
                        case .textDelta(let delta):
                            appendDelta(delta, to: assistantID)
                        case .toolCallStarted(let name):
                            toolStatus = toolStatusText(for: name)
                        case .toolCallCompleted:
                            toolStatus = nil
                        case .completed:
                            break
                        case .error(let error):
                            errorMessage = error.localizedDescription
                        }
                    }
                }

                await MainActor.run {
                    isSending = false
                    toolStatus = nil
                    finalizeRender(for: assistantID)
                    persistAssistantMessageIfNeeded(id: assistantID)
#if DEBUG
                    if let message = messages.first(where: { $0.id == assistantID }) {
                        let contentCount = message.content.count
                        print("[Chat] assistant finished id=\(assistantID) contentCount=\(contentCount) anchor=\(message.sourceAnchorData != nil)")
                    }
#endif
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    toolStatus = nil
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func toolStatusText(for toolName: String) -> String {
        switch toolName {
        case "search_document": return "Searching document..."
        case "read_highlights": return "Reading highlights..."
        case "read_notes": return "Reading notes..."
        default: return "Working..."
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

    // System prompt is now built by AgentLoop.buildSystemPrompt(documentTitle:)

    private func canPin(_ message: ChatMessage) -> Bool {
        guard message.role == .assistant else { return false }
        guard message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return false }
        guard message.sourceAnchorData != nil else { return false }
        return activeDocument != nil
    }

    @MainActor
    private func pinAnswer(_ message: ChatMessage) {
        guard let documentID = activeDocument?.id else { return }
        guard let anchorData = message.sourceAnchorData else { return }

        let existingDescriptor = FetchDescriptor<Annotation>()
        if let existing = try? modelContext.fetch(existingDescriptor),
           existing.contains(where: { annotation in
               annotation.documentID == documentID &&
               annotation.kind == .chatPin &&
               annotation.chatMessageID == message.id
           }) {
            return
        }

        let promptText = message.promptMessageID.flatMap { promptID in
            messages.first(where: { $0.id == promptID })?.content
        }

        let annotation = Annotation(
            documentID: documentID,
            kind: .chatPin,
            anchorData: anchorData,
            quote: message.sourceSelectionText,
            body: message.content,
            chatMessageID: message.id,
            chatPromptID: message.promptMessageID,
            chatPromptSnapshot: promptText
        )

        modelContext.insert(annotation)
        do {
            try modelContext.save()
        } catch {
            print("Failed to save chat pin: \(error)")
        }
    }

    @ViewBuilder
    private func pinnedPreviewCard(_ preview: PinnedChatPreview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                Text("Pinned")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.4))
                Spacer()
                Button(action: { pinnedPreview = nil }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.35))
                }
                .buttonStyle(.plain)
            }

            if let userText = preview.userText, userText.isEmpty == false {
                Text(userText)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .lineLimit(2)
            }

            MarkdownTextView(text: renderMarkdown(preview.assistantText))
                .padding(.leading, 8)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.4))
                        .frame(width: 2)
                }
        }
        .padding(.bottom, 12)
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

    // RAG context resolution is now handled by the agent via the search_document tool

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

    private func finalizeRender(for messageID: UUID) {
        renderNow(for: messageID)
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
        context.coordinator.scheduleHeightUpdate()

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
        context.coordinator.scheduleHeightUpdate()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var height: CGFloat
        @Binding var isFocused: Bool
        let fontSize: CGFloat
        let maxLines: Int
        weak var textView: NSTextView?

        let onSubmit: () -> Void
        private var pendingHeight: CGFloat?

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
            scheduleHeightUpdate()
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

        func scheduleHeightUpdate() {
            guard let textView else { return }
            guard let textContainer = textView.textContainer else { return }
            textView.layoutManager?.ensureLayout(for: textContainer)
            let usedRect = textView.layoutManager?.usedRect(for: textContainer) ?? .zero
            let font = NSFont.systemFont(ofSize: fontSize)
            let lineHeight = font.ascender - font.descender + font.leading
            let maxHeight = lineHeight * CGFloat(maxLines) + (textView.textContainerInset.height * 2)
            let targetHeight = max(lineHeight, min(usedRect.height + (textView.textContainerInset.height * 2), maxHeight))
            guard abs(height - targetHeight) > 0.5 else { return }
            guard pendingHeight != targetHeight else { return }
            pendingHeight = targetHeight
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let newHeight = self.pendingHeight
                self.pendingHeight = nil
                guard let newHeight, abs(self.height - newHeight) > 0.5 else { return }
                self.height = newHeight
            }
        }
    }
}

#Preview {
    ChatView(
        context: .constant(nil),
        messages: .constant([]),
        settings: OpenAISettingsStore(),
        pinnedPreview: .constant(nil),
        activeDocument: .constant(nil)
    )
        .frame(width: 340, height: 300)
        .background(Color(nsColor: .windowBackgroundColor))
}
