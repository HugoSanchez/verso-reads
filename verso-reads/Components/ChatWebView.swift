//
//  ChatWebView.swift
//  verso-reads
//

import SwiftUI
import WebKit

struct ChatWebView: NSViewRepresentable {
    let messages: [ChatMessage]
    let streamingMessageID: UUID?
    let toolStatus: String?
    let isSending: Bool
    let pinnedPreview: PinnedChatPreview?
    let onPinClick: (UUID) -> Void
    let onDismissPin: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPinClick: onPinClick, onDismissPin: onDismissPin)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webpagePreferences = WKWebpagePreferences()
        webpagePreferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = webpagePreferences
        config.userContentController.add(context.coordinator, name: "chat")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator

        if coordinator.didLoad == false {
            loadRenderer(into: webView)
            coordinator.didLoad = true
        }

        guard coordinator.isReady else {
            // Queue state for when ready
            coordinator.pendingMessages = messages
            coordinator.pendingStreamingID = streamingMessageID
            coordinator.pendingToolStatus = toolStatus
            coordinator.pendingThinking = isSending
            return
        }

        // Track which messages are pinned
        var newPinnedIDs: Set<UUID> = []
        if let preview = pinnedPreview {
            newPinnedIDs.insert(preview.id)
            newPinnedIDs.insert(preview.assistantMessageID)
        }

        // If pin state changed, reset the webview to re-render all messages
        if newPinnedIDs != coordinator.lastPinnedIDs {
            coordinator.lastPinnedIDs = newPinnedIDs
            coordinator.pinnedMessageIDs = newPinnedIDs
            coordinator.renderedMessageCount = 0
            coordinator.lastDeltaLength.removeAll()
            coordinator.lastThinkingState = nil
            let js = "window.VersoChatClear && window.VersoChatClear();"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        coordinator.syncMessages(messages, streamingID: streamingMessageID, in: webView)
        coordinator.syncToolStatus(toolStatus, in: webView)
        coordinator.syncThinking(isSending, in: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var didLoad = false
        var isReady = false
        weak var webView: WKWebView?
        private let onPinClick: (UUID) -> Void
        private let onDismissPin: () -> Void

        // Pending state before ready
        var pendingMessages: [ChatMessage]?
        var pendingStreamingID: UUID?
        var pendingToolStatus: String?
        var pendingThinking: Bool?

        // Tracking what's been sent to JS
        var renderedMessageCount = 0
        var lastDeltaLength: [UUID: Int] = [:]
        var lastThinkingState: Bool?

        /// IDs of messages that are part of the pinned preview (rendered with pin badge)
        var pinnedMessageIDs: Set<UUID> = []
        var lastPinnedIDs: Set<UUID> = []

        init(onPinClick: @escaping (UUID) -> Void, onDismissPin: @escaping () -> Void) {
            self.onPinClick = onPinClick
            self.onDismissPin = onDismissPin
        }

        func syncMessages(_ messages: [ChatMessage], streamingID: UUID?, in webView: WKWebView) {
            for (index, message) in messages.enumerated() {
                if index < renderedMessageCount {
                    // Already sent to JS — but check for streaming delta updates
                    if message.id == streamingID {
                        let previousLength = lastDeltaLength[message.id] ?? 0
                        let currentLength = message.content.count
                        if currentLength > previousLength {
                            let delta = String(message.content.dropFirst(previousLength))
                            appendDelta(message.id, delta: delta, in: webView)
                            lastDeltaLength[message.id] = currentLength
                        }
                    }
                    continue
                }

                // New message — add it
                let isPinned = pinnedMessageIDs.contains(message.id)
                if message.id == streamingID {
                    // Streaming message: send as empty, deltas will fill it
                    addMessage(message.id, role: message.role == .user ? "user" : "assistant", content: "", isPinned: isPinned, in: webView)
                    lastDeltaLength[message.id] = 0
                    // Send any existing content as a delta
                    if message.content.isEmpty == false {
                        appendDelta(message.id, delta: message.content, in: webView)
                        lastDeltaLength[message.id] = message.content.count
                    }
                } else {
                    addMessage(message.id, role: message.role == .user ? "user" : "assistant", content: message.content, isPinned: isPinned, in: webView)
                }
                renderedMessageCount = index + 1
            }

            // Check if a previously streaming message is now finalized
            for (messageID, _) in lastDeltaLength {
                if messageID != streamingID {
                    let message = messages.first { $0.id == messageID }
                    let canPin = message?.sourceAnchorData != nil
                    finalizeMessage(messageID, canPin: canPin, in: webView)
                    lastDeltaLength.removeValue(forKey: messageID)
                }
            }
        }

        func syncToolStatus(_ status: String?, in webView: WKWebView) {
            let escaped = status.map { escapeForJS($0) }
            let arg = escaped.map { "\"\($0)\"" } ?? "null"
            let js = "window.VersoChatSetToolStatus && window.VersoChatSetToolStatus(\(arg));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func syncThinking(_ isSending: Bool, in webView: WKWebView) {
            guard isSending != lastThinkingState else { return }
            lastThinkingState = isSending
            let js = "window.VersoChatSetThinking && window.VersoChatSetThinking(\(isSending));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        // MARK: - JS Bridge Calls

        private func addMessage(_ id: UUID, role: String, content: String, isPinned: Bool = false, in webView: WKWebView) {
            let js = "window.VersoChatAddMessage && window.VersoChatAddMessage(\"\(id.uuidString)\", \"\(role)\", \"\(escapeForJS(content))\", \(isPinned));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func appendDelta(_ id: UUID, delta: String, in webView: WKWebView) {
            let js = "window.VersoChatAppendDelta && window.VersoChatAppendDelta(\"\(id.uuidString)\", \"\(escapeForJS(delta))\");"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func finalizeMessage(_ id: UUID, canPin: Bool, in webView: WKWebView) {
            let js = "window.VersoChatFinalizeMessage && window.VersoChatFinalizeMessage(\"\(id.uuidString)\", \(canPin));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func escapeForJS(_ string: String) -> String {
            string
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Navigation finished but wait for JS "ready" message
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow the initial page load and internal navigation
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
                return
            }

            // Open all link clicks in the system browser
            if let url = navigationAction.request.url, url.scheme == "https" || url.scheme == "http" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        // MARK: - WKScriptMessageHandler

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "chat" else { return }
            guard let payload = message.body as? [String: Any],
                  let type = payload["type"] as? String else { return }

            switch type {
            case "ready":
                isReady = true
                // Flush pending state
                if let pending = pendingMessages, let webView = message.webView {
                    syncMessages(pending, streamingID: pendingStreamingID, in: webView)
                    syncToolStatus(pendingToolStatus, in: webView)
                    if let thinking = pendingThinking {
                        syncThinking(thinking, in: webView)
                    }
                    pendingMessages = nil
                    pendingStreamingID = nil
                    pendingToolStatus = nil
                    pendingThinking = nil
                }

            case "pin-click":
                if let messageIdString = payload["messageId"] as? String,
                   let messageId = UUID(uuidString: messageIdString) {
                    DispatchQueue.main.async {
                        self.onPinClick(messageId)
                    }
                }

            case "dismiss-pin":
                DispatchQueue.main.async {
                    self.onDismissPin()
                }

            default:
                break
            }
        }
    }

    private func loadRenderer(into webView: WKWebView) {
        guard let rendererURL = Bundle.main.url(
            forResource: "chat",
            withExtension: "html",
            subdirectory: "ChatRenderer"
        ) else {
            return
        }
        let baseURL = rendererURL.deletingLastPathComponent()
        webView.loadFileURL(rendererURL, allowingReadAccessTo: baseURL)
    }
}
