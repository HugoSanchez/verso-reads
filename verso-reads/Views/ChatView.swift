//
//  ChatView.swift
//  verso-reads
//

import SwiftUI
import AppKit
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var readerSession: ReaderSession
    @EnvironmentObject private var toastManager: ToastManager
    @Binding var context: ChatContext?
    @Binding var messages: [ChatMessage]
    @ObservedObject var settings: OpenAISettingsStore
    @Binding var pinnedPreview: PinnedChatPreview?
    @Binding var activeDocument: LibraryDocument?
    var showInput: Bool = true

    @State private var inputText: String = ""
    @State private var isSending = false
    @State private var streamingMessageID: UUID?
    @State private var inputHeight: CGFloat = 22
    @State private var isInputFocused = false
    @State private var toolStatus: String?
    @State private var activeTask: Task<Void, Never>?

    // Token-based compression replaces the old fixed historyLimit

    var body: some View {
        VStack(spacing: 0) {
            chatContent

            if showInput {
                chatInput
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatContent: some View {
        ChatWebView(
            messages: displayMessages,
            streamingMessageID: streamingMessageID,
            toolStatus: toolStatus,
            isSending: isSending,
            pinnedPreview: pinnedPreview,
            onPinClick: { messageID in
                if let message = messages.first(where: { $0.id == messageID }) {
                    pinAnswer(message)
                }
            },
            onDismissPin: { pinnedPreview = nil }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Messages with pinned Q&A prepended when active
    private var displayMessages: [ChatMessage] {
        guard let preview = pinnedPreview else { return messages }
        var result: [ChatMessage] = []
        if let userText = preview.userText, userText.isEmpty == false {
            result.append(ChatMessage(
                id: preview.id,
                role: .user,
                content: userText
            ))
        }
        result.append(ChatMessage(
            id: preview.assistantMessageID,
            role: .assistant,
            content: preview.assistantText
        ))
        result.append(contentsOf: messages)
        return result
    }

    private var chatInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let context {
                HStack(spacing: 6) {
                    Text("\(context.wordCount) words selected")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                    Button(action: { self.context = nil }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.7))
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

                if isSending {
                    Button(action: cancelGeneration) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.black.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: sendMessage) {
                        Image(systemName: "paperplane")
                            .font(.system(size: 14))
                            .foregroundStyle(sendButtonColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(canSend == false)
                }
            }

            if settings.hasAPIKey == false {
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

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        guard settings.hasAPIKey else { return }

        var historyMessages = messages
        // Prepend pinned Q&A so the LLM has context for follow-up questions
        if let preview = pinnedPreview {
            var pinContext: [ChatMessage] = []
            if let userText = preview.userText, userText.isEmpty == false {
                pinContext.append(ChatMessage(role: .user, content: userText))
            }
            pinContext.append(ChatMessage(role: .assistant, content: preview.assistantText))
            historyMessages = pinContext + historyMessages
        }
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
        streamingMessageID = assistantID
        inputText = ""
        inputHeight = 22
        context = nil
        persistMessage(userMessage)

        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = OpenAIClient(apiKey: apiKey, model: model.isEmpty ? "gpt-5.2-mini" : model)

        isSending = true
        toolStatus = nil

        activeTask = Task {
            do {
                let userPrompt: String
                if let selectionText, selectionText.isEmpty == false {
                    userPrompt = "Selected text:\n\(selectionText)\n\nQuestion:\n\(trimmed)"
                } else {
                    userPrompt = trimmed
                }

                let conversation = await ConversationCompressor.buildConversation(
                    from: historyMessages,
                    userPrompt: userPrompt,
                    client: client
                )
                let documentTitle = activeDocument?.title ?? "Unknown Document"

                let currentSession = readerSession
                let turnID = UUID()
                let executor = ToolExecutor(
                    documentID: activeDocument?.id ?? UUID(),
                    apiKey: apiKey,
                    modelContext: modelContext,
                    document: activeDocument,
                    currentPageProvider: { currentSession.currentPageNumber },
                    readerSession: currentSession,
                    turnID: turnID
                )

                let agentLoop = AgentLoop(
                    client: client,
                    systemPrompt: AgentLoop.buildSystemPrompt(documentTitle: documentTitle),
                    tools: AgentTools.all,
                    toolExecutor: executor
                )

                for try await event in agentLoop.run(messages: conversation) {
                    try Task.checkCancellation()
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
                            setErrorFallback(error.localizedDescription, for: assistantID)
                            toastManager.show(error.localizedDescription, style: .error)
                        }
                    }
                }

                await MainActor.run {
                    isSending = false
                    toolStatus = nil
                    streamingMessageID = nil
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
                    streamingMessageID = nil
                    if error is CancellationError {
                        removeEmptyAssistantMessage(id: assistantID)
                    } else {
                        setErrorFallback(error.localizedDescription, for: assistantID)
                        toastManager.show(error.localizedDescription, style: .error)
                    }
                }
            }
        }
    }

    private func cancelGeneration() {
        activeTask?.cancel()
        activeTask = nil
        isSending = false
        toolStatus = nil
        streamingMessageID = nil
    }

    private func toolStatusText(for toolName: String) -> String {
        switch toolName {
        case "search_document": return "Searching document..."
        case "read_highlights": return "Reading highlights..."
        case "read_notes": return "Reading notes..."
        case "get_document_info": return "Reading document info..."
        case "get_current_page": return "Checking current page..."
        case "get_page_text": return "Reading page text..."
        case "navigate_to_page": return "Navigating..."
        case "create_note": return "Writing note..."
        case "append_to_note": return "Adding to notes..."
        case "create_highlight": return "Highlighting..."
        case "delete_highlight": return "Removing highlight..."
        case "update_highlight": return "Updating highlight..."
        case "undo_last_action": return "Undoing..."
        case "get_library": return "Browsing library..."
        case "get_collections": return "Reading collections..."
        case "get_chat_history": return "Reading chat history..."
        case "search_all_documents": return "Searching library..."
        case "search_arxiv": return "Searching arXiv..."
        case "search_semantic_scholar": return "Searching papers..."
        case "search_pubmed": return "Searching PubMed..."
        case "download_paper": return "Downloading paper..."
        case "add_to_collection": return "Organizing..."
        case "web_search": return "Searching the web..."
        default: return "Working..."
        }
    }

    private var canSend: Bool {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty == false && isSending == false && settings.hasAPIKey
    }

    private var sendButtonColor: Color {
        canSend ? Color.accentColor : Color.black.opacity(0.3)
    }

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

    // Conversation building is now handled by ConversationCompressor

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

    private func setErrorFallback(_ errorDescription: String, for assistantID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }
        if messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages[index].content = "Sorry, something went wrong. Please try again."
        }
    }

    private func removeEmptyAssistantMessage(id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        if messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.remove(at: index)
        }
    }

    private func appendDelta(_ delta: String, to assistantID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return }
        messages[index].content += delta
        // SwiftUI state change triggers ChatWebView.updateNSView → coordinator syncs delta to JS
    }
}

private final class PlainPasteTextView: NSTextView {
    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
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

        let textView = PlainPasteTextView()
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.backgroundColor = .clear
        textView.isRichText = false
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
        .environmentObject(ToastManager())
        .frame(width: 340, height: 300)
        .background(Color(nsColor: .windowBackgroundColor))
}
