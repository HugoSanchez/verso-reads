//
//  ReaderToolbar.swift
//  verso-reads
//

import SwiftUI

struct ReaderToolbar: View {
    let title: String
    @Binding var isRightPanelVisible: Bool
    @Binding var highlightColor: HighlightColor
    let onHighlight: (HighlightColor) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.85))

                Spacer()

                HStack(spacing: 16) {
                    Menu {
                        ForEach(HighlightColor.allCases) { color in
                            Button {
                                highlightColor = color
                                onHighlight(color)
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(color.swatch)
                                        .frame(width: 10, height: 10)
                                    Text(color.label)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "highlighter")
                            .foregroundStyle(highlightColor.swatch.opacity(0.95))
                    }
                    Button(action: {}) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    Button(action: {}) {
                        Text("AA")
                            .font(.system(size: 13, weight: .medium))
                    }
                    Button(action: toggleRightPanel) {
                        Image(systemName: "sidebar.right")
                            .foregroundStyle(isRightPanelVisible ? Color.accentColor : Color.black.opacity(0.4))
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Color.black.opacity(0.4))
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Subtle separator line
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 1)
                .padding(.horizontal, 24)
        }
    }

    private func toggleRightPanel() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isRightPanelVisible.toggle()
        }
    }
}

#Preview {
    ReaderToolbar(
        title: "New reading",
        isRightPanelVisible: .constant(false),
        highlightColor: .constant(.yellow),
        onHighlight: { _ in }
    )
    .background(Color.white)
}
