//
//  MarkdownTextView.swift
//  verso-reads
//

import SwiftUI
import MarkdownUI

struct MarkdownTextView: View {
    let content: MarkdownContent
    var fontSize: CGFloat = 12
    var textColor: Color = Color.black.opacity(0.85)

    var body: some View {
        Markdown(content)
            .font(.system(size: fontSize))
            .foregroundStyle(textColor)
            .fixedSize(horizontal: false, vertical: true)
    }
}
