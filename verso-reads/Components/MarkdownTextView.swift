//
//  MarkdownTextView.swift
//  verso-reads
//

import SwiftUI
import AppKit

struct MarkdownTextView: NSViewRepresentable {
    let text: NSAttributedString

    func makeNSView(context: Context) -> AutoSizingTextView {
        let textView = AutoSizingTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = .zero
        textView.textStorage?.setAttributedString(text)
        return textView
    }

    func updateNSView(_ nsView: AutoSizingTextView, context: Context) {
        if nsView.attributedString() != text {
            nsView.textStorage?.setAttributedString(text)
            nsView.invalidateIntrinsicContentSize()
        }
    }
}

final class AutoSizingTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let layoutManager = layoutManager, let textContainer = textContainer else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(usedRect.height))
    }
}
