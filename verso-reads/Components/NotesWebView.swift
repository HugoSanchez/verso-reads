//
//  NotesWebView.swift
//  verso-reads
//

import SwiftUI
import WebKit

struct NotesWebView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.setValue(false, forKey: "drawsBackground")
        webView.enclosingScrollView?.hasVerticalScroller = false
        webView.enclosingScrollView?.hasHorizontalScroller = false
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.didLoad == false else { return }
        webView.loadHTMLString(Self.editorHTML, baseURL: nil)
        context.coordinator.didLoad = true
    }

    final class Coordinator {
        var didLoad = false
    }

    private static let editorHTML: String = #"""
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
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
        }
        .ProseMirror {
          outline: none;
          padding: 0;
          min-height: 100%;
          box-sizing: border-box;
          line-height: 1.55;
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
      <script type="module">
        import { Editor } from "https://esm.sh/@tiptap/core@2.11.1";
        import StarterKit from "https://esm.sh/@tiptap/starter-kit@2.11.1";
        import Placeholder from "https://esm.sh/@tiptap/extension-placeholder@2.11.1";

        new Editor({
          element: document.querySelector("#editor"),
          extensions: [
            StarterKit.configure({
              heading: { levels: [1, 2, 3] }
            }),
            Placeholder.configure({
              placeholder: "Start typing…",
            }),
          ],
          editorProps: {
            attributes: {
              spellcheck: "true",
              autocapitalize: "sentences",
              autocorrect: "on"
            }
          }
        });
      </script>
    </body>
    </html>
    """#
}

#Preview {
    NotesWebView()
        .frame(width: 320, height: 320)
}
