//
//  MarkdownRenderer.swift
//  verso-reads
//

import Foundation
import CoreGraphics
import Down

enum MarkdownRenderer {
    private static let debugEnabled: Bool = {
        if ProcessInfo.processInfo.environment["VERSO_DEBUG_MARKDOWN"] == "1" {
            return true
        }
        return UserDefaults.standard.bool(forKey: "debug.markdown")
    }()

    static func renderHTML(_ markdown: String, fontSize: CGFloat, textColorCSS: String) -> String {
        let htmlBody = (try? Down(markdownString: markdown).toHTML()) ?? fallbackHTML(from: markdown)

        if debugEnabled {
            print("=== MarkdownRenderer ===")
            print("--- raw markdown ---")
            print(markdown)
            print("--- html body ---")
            print(htmlBody)
            print("=== end ===")
        }

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <style>
            :root { color-scheme: light; }
            html, body { margin: 0; padding: 0; }
            body {
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif;
              font-size: \(fontSize)px;
              color: \(textColorCSS);
              line-height: 1.55;
              padding: 0 3px;
            }
            p { margin: 0 0 0.75em; }
            p:last-child { margin-bottom: 0; }
            ul, ol { margin: 0 0 0.75em 1.2em; padding: 0; }
            li { margin: 0 0 0.35em; }
            li:last-child { margin-bottom: 0; }
            blockquote {
              margin: 0 0 0.75em;
              padding-left: 12px;
              border-left: 2px solid rgba(0, 0, 0, 0.1);
              color: rgba(0, 0, 0, 0.7);
            }
            code {
              font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
              font-size: 0.95em;
              background: rgba(0, 0, 0, 0.06);
              padding: 0.05em 0.2em;
              border-radius: 4px;
            }
            pre code {
              display: block;
              padding: 0.6em;
            }
          </style>
        </head>
        <body>
          \(htmlBody)
        </body>
        </html>
        """
    }

    private static func fallbackHTML(from markdown: String) -> String {
        let escaped = markdown
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "\n", with: "<br>")
        return "<p>\(escaped)</p>"
    }
}
