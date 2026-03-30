//
//  MarkdownRenderer.swift
//  verso-reads
//

import Foundation
import CoreGraphics
import AppKit
import Down

enum MarkdownRenderer {

    // MARK: - Primary render path (AST → NSAttributedString, no HTML/WebKit)

    static func renderAttributed(_ markdown: String, fontSize: CGFloat, textColor: NSColor) -> NSAttributedString {
        let styler = buildStyler(fontSize: fontSize, textColor: textColor)

        do {
            return try Down(markdownString: markdown).toAttributedString(.default, styler: styler)
        } catch {
            // Fallback: plain styled text
            return NSAttributedString(
                string: markdown,
                attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize),
                    .foregroundColor: textColor
                ]
            )
        }
    }

    // MARK: - Styler Configuration

    private static func buildStyler(fontSize: CGFloat, textColor: NSColor) -> DownStyler {
        let fonts = StaticFontCollection(
            heading1: .boldSystemFont(ofSize: fontSize * 1.4),
            heading2: .boldSystemFont(ofSize: fontSize * 1.25),
            heading3: .boldSystemFont(ofSize: fontSize * 1.1),
            heading4: .boldSystemFont(ofSize: fontSize),
            heading5: .boldSystemFont(ofSize: fontSize),
            heading6: .boldSystemFont(ofSize: fontSize),
            body: .systemFont(ofSize: fontSize),
            code: NSFont(name: "Menlo", size: fontSize * 0.92) ?? .monospacedSystemFont(ofSize: fontSize * 0.92, weight: .regular),
            listItemPrefix: .monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        )

        let colors = StaticColorCollection(
            heading1: textColor,
            heading2: textColor,
            heading3: textColor,
            heading4: textColor,
            heading5: textColor,
            heading6: textColor,
            body: textColor,
            code: textColor,
            link: .systemBlue,
            quote: NSColor.black.withAlphaComponent(0.6),
            quoteStripe: NSColor.black.withAlphaComponent(0.15),
            thematicBreak: NSColor.black.withAlphaComponent(0.1),
            listItemPrefix: NSColor.black.withAlphaComponent(0.35),
            codeBlockBackground: NSColor.black.withAlphaComponent(0.04)
        )

        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.paragraphSpacing = fontSize * 0.6
        bodyStyle.lineSpacing = fontSize * 0.35

        let headingStyle = NSMutableParagraphStyle()
        headingStyle.paragraphSpacing = fontSize * 0.5
        headingStyle.paragraphSpacingBefore = fontSize * 0.3

        let codeStyle = NSMutableParagraphStyle()
        codeStyle.paragraphSpacing = fontSize * 0.4

        var paragraphStyles = StaticParagraphStyleCollection()
        paragraphStyles.heading1 = headingStyle
        paragraphStyles.heading2 = headingStyle
        paragraphStyles.heading3 = headingStyle
        paragraphStyles.body = bodyStyle
        paragraphStyles.code = codeStyle

        let listItemOptions = ListItemOptions(
            maxPrefixDigits: 2,
            spacingAfterPrefix: fontSize * 0.5,
            spacingAbove: fontSize * 0.35,
            spacingBelow: fontSize * 0.5
        )

        let quoteStripeOptions = QuoteStripeOptions(
            thickness: 2,
            spacingAfter: fontSize * 0.6
        )

        let codeBlockOptions = CodeBlockOptions(
            containerInset: fontSize * 0.5
        )

        let config = DownStylerConfiguration(
            fonts: fonts,
            colors: colors,
            paragraphStyles: paragraphStyles,
            listItemOptions: listItemOptions,
            quoteStripeOptions: quoteStripeOptions,
            codeBlockOptions: codeBlockOptions
        )

        return DownStyler(configuration: config)
    }

    // MARK: - HTML render (kept for pinned preview and other non-streaming uses)

    static func renderHTML(_ markdown: String, fontSize: CGFloat, textColorCSS: String) -> String {
        let htmlBody = (try? Down(markdownString: markdown).toHTML()) ?? fallbackHTML(from: markdown)

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
