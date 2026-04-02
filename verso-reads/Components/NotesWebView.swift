//
//  NotesWebView.swift
//  verso-reads
//

import SwiftUI
import WebKit

struct QuoteInsertion: Equatable {
    let quote: String
    let annotationId: UUID
}

struct NotesWebView: NSViewRepresentable {
    let content: String
    let documentID: UUID?
    let pendingQuoteInsertion: QuoteInsertion?
    let pendingTextAppend: String?
    let onContentChange: (String) -> Void
    let onQuoteClick: (UUID) -> Void
    let onQuoteRemove: (UUID) -> Void
    let onQuoteInserted: () -> Void
    let onTextAppended: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onContentChange: onContentChange, onQuoteClick: onQuoteClick, onQuoteRemove: onQuoteRemove, onQuoteInserted: onQuoteInserted, onTextAppended: onTextAppended)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webpagePreferences = WKWebpagePreferences()
        webpagePreferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = webpagePreferences
        config.userContentController.add(context.coordinator, name: "notes")

        let webView = NotesWKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        applyScrollbarSettings(to: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        applyScrollbarSettings(to: webView)

        if context.coordinator.didLoad == false {
            loadEditor(into: webView)
            context.coordinator.didLoad = true
        }

        // Reset caches when document changes to ensure fresh content is applied
        if context.coordinator.currentDocumentID != documentID {
            context.coordinator.resetForDocumentChange(documentID)
        }

        context.coordinator.queueContent(content, for: webView)

        if let insertion = pendingQuoteInsertion {
            context.coordinator.insertQuote(insertion, into: webView)
        }

        if let text = pendingTextAppend {
            context.coordinator.appendText(text, into: webView)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var didLoad = false
        var isReady = false
        var currentDocumentID: UUID?
        private var lastAppliedContent: String?
        private var lastEmittedContent: String?
        private var pendingContent: String?
        private var lastInsertedQuoteId: UUID?
        private var pendingQuoteInsertion: QuoteInsertion?
        private var lastAppendedText: String?
        private let onContentChange: (String) -> Void
        private let onQuoteClick: (UUID) -> Void
        private let onQuoteRemove: (UUID) -> Void
        private let onQuoteInserted: () -> Void
        private let onTextAppended: () -> Void

        init(onContentChange: @escaping (String) -> Void, onQuoteClick: @escaping (UUID) -> Void, onQuoteRemove: @escaping (UUID) -> Void, onQuoteInserted: @escaping () -> Void, onTextAppended: @escaping () -> Void) {
            self.onContentChange = onContentChange
            self.onQuoteClick = onQuoteClick
            self.onQuoteRemove = onQuoteRemove
            self.onQuoteInserted = onQuoteInserted
            self.onTextAppended = onTextAppended
        }

        func resetForDocumentChange(_ newDocumentID: UUID?) {
            currentDocumentID = newDocumentID
            lastAppliedContent = nil
            lastEmittedContent = nil
            pendingContent = nil
            lastInsertedQuoteId = nil
            pendingQuoteInsertion = nil
            print("[NotesWebView] reset for document change: \(newDocumentID?.uuidString ?? "nil")")
        }

        func insertQuote(_ insertion: QuoteInsertion, into webView: WKWebView) {
            guard lastInsertedQuoteId != insertion.annotationId else { return }

            if isReady == false {
                // Queue the insertion for when editor is ready
                pendingQuoteInsertion = insertion
                print("[NotesWebView] queued quote insertion for when ready")
                return
            }

            executeQuoteInsertion(insertion, into: webView)
        }

        private func executeQuoteInsertion(_ insertion: QuoteInsertion, into webView: WKWebView) {
            lastInsertedQuoteId = insertion.annotationId

            let escapedQuote = insertion.quote
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            let js = "window.VersoNotesInsertQuote && window.VersoNotesInsertQuote(\"\(escapedQuote)\", \"\(insertion.annotationId.uuidString)\");"
            print("[NotesWebView] executing quote insertion: \(insertion.annotationId)")
            webView.evaluateJavaScript(js) { [weak self] _, _ in
                self?.onQuoteInserted()
            }
        }

        func appendText(_ text: String, into webView: WKWebView) {
            guard lastAppendedText != text else { return }

            if isReady == false {
                print("[NotesWebView] appendText queued: editor not ready")
                return
            }

            lastAppendedText = text

            let escaped = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            let js = "window.VersoNotesAppendText && window.VersoNotesAppendText(\"\(escaped)\");"
            print("[NotesWebView] executing appendText (length=\(text.count))")
            webView.evaluateJavaScript(js) { [weak self] _, error in
                if let error {
                    print("[NotesWebView] appendText JS error: \(error)")
                } else {
                    print("[NotesWebView] appendText JS OK")
                }
                self?.onTextAppended()
            }
        }

        func queueContent(_ content: String, for webView: WKWebView) {
            if let lastEmitted = lastEmittedContent, content == lastEmitted {
                print("[NotesWebView] queueContent SKIPPED: matches lastEmittedContent (length=\(content.count))")
                return
            }
            if isReady == false {
                pendingContent = content
                print("[NotesWebView] queueContent QUEUED: editor not ready yet")
                return
            }
            print("[NotesWebView] queueContent → applyContent (length=\(content.count))")
            applyContent(content, to: webView)
        }

        func applyContent(_ content: String, to webView: WKWebView) {
            guard content != lastAppliedContent else {
                print("[NotesWebView] applyContent SKIPPED: matches lastAppliedContent")
                return
            }
            lastAppliedContent = content

            // Escape the JSON string for JavaScript
            let escaped = content
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            let js = "window.VersoNotesSetContent && window.VersoNotesSetContent(\"\(escaped)\");"
            print("[NotesWebView] applyContent CALLING JS VersoNotesSetContent (length=\(content.count))")
            webView.evaluateJavaScript(js) { result, error in
                if let error {
                    print("[NotesWebView] JS VersoNotesSetContent ERROR: \(error)")
                } else {
                    print("[NotesWebView] JS VersoNotesSetContent OK, result=\(String(describing: result))")
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let pending = pendingContent {
                applyContent(pending, to: webView)
                pendingContent = nil
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "notes" else { return }
            guard let payload = message.body as? [String: Any],
                  let type = payload["type"] as? String else { return }

            print("[NotesWebView] received message: \(type)")

            switch type {
            case "ready":
                isReady = true
                print("[NotesWebView] editor ready")
                if let pending = pendingContent, let webView = message.webView {
                    applyContent(pending, to: webView)
                    pendingContent = nil
                }
                // Process any queued quote insertion
                if let pendingQuote = pendingQuoteInsertion, let webView = message.webView {
                    pendingQuoteInsertion = nil
                    executeQuoteInsertion(pendingQuote, into: webView)
                }

            case "content":
                if let json = payload["json"] {
                    let jsonString: String
                    if let data = try? JSONSerialization.data(withJSONObject: json),
                       let str = String(data: data, encoding: .utf8) {
                        jsonString = str
                    } else {
                        jsonString = ""
                    }
                    print("[NotesWebView] content received, length=\(jsonString.count)")
                    lastEmittedContent = jsonString
                    DispatchQueue.main.async {
                        self.onContentChange(jsonString)
                    }
                } else {
                    print("[NotesWebView] content message but no json payload")
                }

            case "quote-click":
                if let annotationIdString = payload["annotationId"] as? String,
                   let annotationId = UUID(uuidString: annotationIdString) {
                    DispatchQueue.main.async {
                        self.onQuoteClick(annotationId)
                    }
                }

            case "quote-remove":
                if let annotationIdString = payload["annotationId"] as? String,
                   let annotationId = UUID(uuidString: annotationIdString) {
                    DispatchQueue.main.async {
                        self.onQuoteRemove(annotationId)
                    }
                }

            case "debug":
                if let message = payload["message"] as? String {
                    print("[NotesWebView JS] \(message)")
                }

            default:
                break
            }
        }
    }

    private func applyScrollbarSettings(to webView: WKWebView) {
        if let enclosing = webView.enclosingScrollView {
            hideScrollbars(for: enclosing)
        }
        for nestedScrollView in findScrollViews(in: webView) {
            hideScrollbars(for: nestedScrollView)
        }
    }

    private func hideScrollbars(for scrollView: NSScrollView) {
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScroller?.isHidden = true
        scrollView.horizontalScroller?.isHidden = true
        scrollView.verticalScroller?.alphaValue = 0
        scrollView.horizontalScroller?.alphaValue = 0
    }

    private func findScrollViews(in view: NSView) -> [NSScrollView] {
        var results: [NSScrollView] = []
        if let scrollView = view as? NSScrollView {
            results.append(scrollView)
        }
        for subview in view.subviews {
            results.append(contentsOf: findScrollViews(in: subview))
        }
        return results
    }

    private func loadEditor(into webView: WKWebView) {
        guard let editorURL = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "NotesEditor"
        ) else {
            return
        }
        let baseURL = editorURL.deletingLastPathComponent()
        webView.loadFileURL(editorURL, allowingReadAccessTo: baseURL)
    }
}

private final class NotesWKWebView: WKWebView {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        window?.makeFirstResponder(self)
    }
}

#Preview {
    NotesWebView(
        content: "",
        documentID: nil,
        pendingQuoteInsertion: nil,
        pendingTextAppend: nil,
        onContentChange: { _ in },
        onQuoteClick: { _ in },
        onQuoteRemove: { _ in },
        onQuoteInserted: {},
        onTextAppended: {}
    )
    .frame(width: 320, height: 320)
}
