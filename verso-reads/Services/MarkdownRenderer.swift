//
//  MarkdownRenderer.swift
//  verso-reads
//

import AppKit
import Down

enum MarkdownRenderer {
    private static let listItemRegex = try! NSRegularExpression(pattern: #"^\s*(?:[-+*]|\d+\.)\s+"#)
    private static let debugEnabled: Bool = {
        if ProcessInfo.processInfo.environment["VERSO_DEBUG_MARKDOWN"] == "1" {
            return true
        }
        return UserDefaults.standard.bool(forKey: "debug.markdown")
    }()

    static func render(_ markdown: String, fontSize: CGFloat, textColor: NSColor) -> NSAttributedString {
        let normalized = normalizeListSpacing(in: markdown)
        let rendered = (try? Down(markdownString: normalized).toAttributedString())
            ?? NSAttributedString(string: markdown)

        if debugEnabled {
            print("=== MarkdownRenderer ===")
            print("--- raw markdown ---")
            print(markdown)
            if normalized != markdown {
                print("--- normalized markdown ---")
                print(normalized)
            }
            print("--- rendered string ---")
            print(rendered.string)
            print("=== end ===")
        }

        let mutable = NSMutableAttributedString(attributedString: rendered)
        let fullRange = NSRange(location: 0, length: mutable.length)
        let baseFont = NSFont.systemFont(ofSize: fontSize)

        mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            let currentFont = value as? NSFont ?? baseFont
            let traits = currentFont.fontDescriptor.symbolicTraits
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
            let newFont = NSFont(descriptor: descriptor, size: fontSize) ?? baseFont
            mutable.addAttribute(.font, value: newFont, range: range)
        }

        normalizeParagraphIndents(in: mutable)
        mutable.addAttribute(.foregroundColor, value: textColor, range: fullRange)
        return mutable
    }

    private static func normalizeListSpacing(in markdown: String) -> String {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        output.reserveCapacity(lines.count + 4)

        for index in lines.indices {
            let line = lines[index]
            output.append(line)
            guard isListItem(line) else { continue }

            var nextIndex = index + 1
            guard nextIndex < lines.count else { continue }
            while nextIndex < lines.count, lines[nextIndex].trimmingCharacters(in: .whitespaces).isEmpty {
                nextIndex += 1
            }
            guard nextIndex < lines.count else { continue }
            let nextLine = lines[nextIndex]
            if isListItem(nextLine) || nextLine.hasPrefix("  ") || nextLine.hasPrefix("\t") {
                continue
            }
            if nextIndex == index + 1 {
                output.append("")
            }
        }

        return output.joined(separator: "\n")
    }

    private static func isListItem(_ line: String) -> Bool {
        let range = NSRange(location: 0, length: line.utf16.count)
        return listItemRegex.firstMatch(in: line, options: [], range: range) != nil
    }

    private static func normalizeParagraphIndents(in attributed: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.paragraphStyle, in: fullRange, options: []) { value, range, _ in
            guard let style = value as? NSParagraphStyle else { return }
            if style.textLists.isEmpty == false {
                return
            }
            if style.firstLineHeadIndent == 0,
               style.headIndent == 0,
               style.tabStops.isEmpty {
                return
            }
            let mutableStyle = style.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            mutableStyle.firstLineHeadIndent = 0
            mutableStyle.headIndent = 0
            mutableStyle.tabStops = []
            attributed.addAttribute(.paragraphStyle, value: mutableStyle, range: range)
        }
    }
}
