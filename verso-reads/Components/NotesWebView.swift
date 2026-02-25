//
//  NotesWebView.swift
//  verso-reads
//

import SwiftUI
import WebKit

struct NotesWebView: NSViewRepresentable {
    let markdown: String
    let onMarkdownChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMarkdownChange: onMarkdownChange)
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
        DispatchQueue.main.async {
            applyScrollbarSettings(to: webView)
        }
        if context.coordinator.didLoad == false {
            loadEditor(into: webView)
            context.coordinator.didLoad = true
        }

        context.coordinator.queueMarkdown(markdown, for: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var didLoad = false
        var isReady = false
        private var lastAppliedMarkdown: String?
        private var lastEmittedMarkdown: String?
        private var lastObservedMarkdown: String?
        private var pendingMarkdown: String?
        private var pollTimer: Timer?
        private let onMarkdownChange: (String) -> Void

        init(onMarkdownChange: @escaping (String) -> Void) {
            self.onMarkdownChange = onMarkdownChange
        }

        deinit {
            stopPolling()
        }

        func queueMarkdown(_ markdown: String, for webView: WKWebView) {
            if let lastEmitted = lastEmittedMarkdown, markdown == lastEmitted {
                return
            }
            if isReady == false {
                pendingMarkdown = markdown
                return
            }
            applyMarkdown(markdown, to: webView)
        }

        func applyMarkdown(_ markdown: String, to webView: WKWebView) {
            guard markdown != lastAppliedMarkdown else { return }
            lastAppliedMarkdown = markdown
            lastObservedMarkdown = markdown
            let payload = (try? JSONEncoder().encode(markdown))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
            let js = "window.VersoNotesSetContent && window.VersoNotesSetContent(\(payload));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let pending = pendingMarkdown {
                applyMarkdown(pending, to: webView)
                pendingMarkdown = nil
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "notes" else { return }
            if let payload = message.body as? [String: Any],
               let type = payload["type"] as? String {
                if type == "ready" {
                    isReady = true
                    if let pending = pendingMarkdown {
                        if let webView = message.webView {
                            applyMarkdown(pending, to: webView)
                            startPolling(with: webView)
                        }
                        pendingMarkdown = nil
                    }
                    if let webView = message.webView {
                        startPolling(with: webView)
                    }
                    return
                }
                if type == "markdown", let markdown = payload["markdown"] as? String {
                    lastEmittedMarkdown = markdown
                    DispatchQueue.main.async {
                        self.onMarkdownChange(markdown)
                    }
                }
            }
        }

        private func startPolling(with webView: WKWebView) {
            guard pollTimer == nil else { return }
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self, weak webView] _ in
                guard let self, let webView else { return }
                let js = "window.VersoNotesGetMarkdown && window.VersoNotesGetMarkdown();"
                webView.evaluateJavaScript(js) { result, _ in
                    guard let markdown = result as? String else { return }
                    if markdown == self.lastObservedMarkdown { return }
                    self.lastObservedMarkdown = markdown
                    if markdown == self.lastEmittedMarkdown { return }
                    self.lastEmittedMarkdown = markdown
                    DispatchQueue.main.async {
                        self.onMarkdownChange(markdown)
                    }
                }
            }
            pollTimer?.tolerance = 0.2
        }

        private func stopPolling() {
            pollTimer?.invalidate()
            pollTimer = nil
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
            webView.loadHTMLString(Self.fallbackHTML, baseURL: nil)
            return
        }
        let baseURL = editorURL.deletingLastPathComponent()
        webView.loadFileURL(editorURL, allowingReadAccessTo: baseURL)
    }

    private static let fallbackHTML: String = #"""
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>Verso Notes</title>
      <style>
        :root {
          color-scheme: light;
        }
        html, body {
          height: 100%;
          margin: 0;
          padding: 0;
          background: transparent;
        }
        body {
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif;
          font-size: 12px;
          color: rgba(0, 0, 0, 0.85);
          overflow: auto;
          scrollbar-width: none;
        }
        #editor {
          height: 100%;
          width: 100%;
          min-width: 100%;
          box-sizing: border-box;
        }
        .ProseMirror {
          width: 100%;
          min-width: 100%;
          box-sizing: border-box;
          display: block;
          outline: none;
          padding: 26px 38px 26px 26px;
          min-height: 100%;
          line-height: 1.55;
          white-space: pre-wrap;
          word-break: break-word;
        }
        body::-webkit-scrollbar {
          width: 0;
          height: 0;
        }
        .ProseMirror p {
          margin: 0 0 0.75em;
        }
        .ProseMirror h1 {
          font-size: 20px;
          margin: 0 0 0.6em;
        }
        .ProseMirror h2 {
          font-size: 18px;
          margin: 0 0 0.6em;
        }
        .ProseMirror blockquote {
          margin: 0 0 0.75em;
          padding-left: 12px;
          border-left: 2px solid rgba(0, 0, 0, 0.1);
          color: rgba(0, 0, 0, 0.7);
        }
        .ProseMirror-focused {
          outline: none;
        }
        .is-editor-empty:first-child::before {
          content: attr(data-placeholder);
          float: left;
          color: rgba(0, 0, 0, 0.3);
          pointer-events: none;
          height: 0;
        }
      </style>
    </head>
    <body>
      <div id="editor"></div>
      <script>
        (() => {
          const placeholderText = "Start typing...";
          const editor = document.querySelector("#editor");
          if (!editor) {
            return;
          }
          editor.className = "ProseMirror";
          editor.setAttribute("contenteditable", "true");
          editor.setAttribute("spellcheck", "true");
          editor.setAttribute("autocapitalize", "sentences");
          editor.setAttribute("autocorrect", "on");
          editor.setAttribute("data-placeholder", placeholderText);
          editor.setAttribute("tabindex", "0");

          const isEditorEmpty = () => {
            const text = editor.textContent || "";
            if (text.trim().length > 0) {
              return false;
            }
            const html = editor.innerHTML
              .replace(/<br\\s*\\/?>/gi, "")
              .replace(/&nbsp;/g, "")
              .replace(/\\s+/g, "")
              .trim();
            return html.length === 0;
          };

          const updatePlaceholder = () => {
            if (isEditorEmpty()) {
              editor.classList.add("is-editor-empty");
            } else {
              editor.classList.remove("is-editor-empty");
            }
          };

          window.VersoNotesSetContent = (markdown) => {
            const text = typeof markdown === "string" ? markdown : "";
            editor.innerText = text;
            updatePlaceholder();
          };

          const ensureParagraphOnEnter = (event) => {
            if (event.key !== "Enter") {
              return;
            }
            if (event.shiftKey) {
              return;
            }
            if (document.queryCommandSupported("insertParagraph")) {
              event.preventDefault();
              document.execCommand("insertParagraph", false);
            }
          };

          const applyShortcut = (event) => {
            if (!event.metaKey) {
              return false;
            }
            if (event.shiftKey || event.altKey || event.ctrlKey) {
              return false;
            }
            const key = event.key.toLowerCase();
            if (key !== "b" && key !== "i") {
              return false;
            }
            event.preventDefault();
            document.execCommand(key === "b" ? "bold" : "italic", false);
            return true;
          };

          editor.addEventListener("input", updatePlaceholder);
          editor.addEventListener("focus", () => editor.classList.add("ProseMirror-focused"));
          editor.addEventListener("blur", () => editor.classList.remove("ProseMirror-focused"));
          editor.addEventListener("keydown", (event) => {
            if (applyShortcut(event)) {
              return;
            }
            ensureParagraphOnEnter(event);
          });

          updatePlaceholder();
          setTimeout(() => editor.focus(), 0);
          const postMarkdown = () => {
            if (!window.webkit?.messageHandlers?.notes) {
              return;
            }
            const text = editor.innerText || "";
            window.webkit.messageHandlers.notes.postMessage({
              type: "markdown",
              markdown: text
            });
          };
          let debounceTimer;
          editor.addEventListener("input", () => {
            updatePlaceholder();
            clearTimeout(debounceTimer);
            debounceTimer = setTimeout(postMarkdown, 400);
          });
          window.webkit?.messageHandlers?.notes?.postMessage({ type: "ready" });
        })();
      </script>
    </body>
    </html>
    """#
}

private final class NotesWKWebView: WKWebView {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        window?.makeFirstResponder(self)
    }
}

#Preview {
    NotesWebView(markdown: "", onMarkdownChange: { _ in })
        .frame(width: 320, height: 320)
}
