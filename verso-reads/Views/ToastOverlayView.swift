//
//  ToastOverlayView.swift
//  verso-reads
//

import SwiftUI

struct ToastOverlayView: View {
    @EnvironmentObject private var toastManager: ToastManager

    var body: some View {
        VStack(spacing: 8) {
            ForEach(toastManager.toasts) { toast in
                toastCard(toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 44)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(!toastManager.toasts.isEmpty)
    }

    private func toastCard(_ toast: ToastItem) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1)
                .fill(accentColor(for: toast.style))
                .frame(width: 2, height: 16)

            Text(toast.message)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.8))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                toastManager.dismiss(toast.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 380)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: NSColor(white: 0.15, alpha: 0.92)))
                .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
        )
    }

    private func accentColor(for style: ToastStyle) -> Color {
        switch style {
        case .error:
            return Color.white.opacity(0.45)
        case .info:
            return Color.white.opacity(0.2)
        }
    }
}
