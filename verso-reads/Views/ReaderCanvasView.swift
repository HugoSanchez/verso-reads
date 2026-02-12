//
//  ReaderCanvasView.swift
//  verso-reads
//

import SwiftUI

struct ReaderCanvasView: View {
    @Binding var isRightPanelVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New reading")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.85))
                Spacer()
                HStack(spacing: 16) {
                    Button(action: {}) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    Button(action: {}) {
                        Text("AA")
                            .font(.system(size: 13, weight: .medium))
                    }
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRightPanelVisible.toggle()
                        }
                    }) {
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

            // Empty state
            VStack(spacing: 14) {
                Image(systemName: "doc.text")
                    .font(.system(size: 42, weight: .thin))
                    .foregroundStyle(Color.black.opacity(0.3))
                Text("Drop a document to start reading")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.85))
                Text("We will keep your place, highlights, and notes in sync.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black.opacity(0.45))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    ReaderCanvasView(isRightPanelVisible: .constant(false))
        .frame(width: 800, height: 600)
}
