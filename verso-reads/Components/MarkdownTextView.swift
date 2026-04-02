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
        guard nsView.textStorage?.length != text.length || nsView.attributedString() != text else {
            return
        }
        nsView.textStorage?.setAttributedString(text)
        nsView.scheduleInvalidation()
    }
}

final class AutoSizingTextView: NSTextView {
    private var invalidationScheduled = false

    override var intrinsicContentSize: NSSize {
        guard let layoutManager = layoutManager, let textContainer = textContainer else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(usedRect.height))
    }

    /// Coalesce rapid invalidation calls into a single layout pass.
    /// During streaming, updateNSView fires many times per second;
    /// this ensures we only recalculate intrinsic size once per frame.
    func scheduleInvalidation() {
        guard invalidationScheduled == false else { return }
        invalidationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.invalidationScheduled = false
            self.invalidateIntrinsicContentSize()
        }
    }
}
