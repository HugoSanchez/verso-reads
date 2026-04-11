//
//  HighlightEditPopover.swift
//  verso-reads
//

import SwiftUI
import AppKit

struct HighlightEditPopover: View {
    let currentColor: String?
    let onColorChange: (HighlightColor) -> Void
    let onAddToChat: () -> Void
    let onAddToNotes: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            colorSwatches

            separator

            actionButton(title: "Add to chat", systemImage: "plus", action: onAddToChat)

            separator

            actionButton(title: "Add to scratchpad", systemImage: "note.text", action: onAddToNotes)

            separator

            removeButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 4)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.black.opacity(0.15))
            .frame(width: 1, height: 14)
    }

    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.black.opacity(0.5))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var colorSwatches: some View {
        HStack(spacing: 5) {
            ForEach(HighlightColor.allCases) { color in
                Button {
                    onColorChange(color)
                } label: {
                    Circle()
                        .fill(color.swatch)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                        )
                        .overlay(checkmark(for: color))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func checkmark(for color: HighlightColor) -> some View {
        if currentColor == color.rawValue {
            Image(systemName: "checkmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.5))
        }
    }

    private var removeButton: some View {
        Button {
            onRemove()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .medium))
                Text("Remove")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.black.opacity(0.5))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

#Preview {
    HighlightEditPopover(
        currentColor: "yellow",
        onColorChange: { _ in },
        onAddToChat: {},
        onAddToNotes: {},
        onRemove: {}
    )
    .padding()
    .background(Color.gray.opacity(0.2))
}
