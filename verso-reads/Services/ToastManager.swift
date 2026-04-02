//
//  ToastManager.swift
//  verso-reads
//

import SwiftUI
import Combine

enum ToastStyle {
    case error
    case info
}

struct ToastItem: Identifiable {
    let id = UUID()
    let message: String
    let style: ToastStyle
    let timestamp = Date()
}

final class ToastManager: ObservableObject {
    @Published private(set) var toasts: [ToastItem] = []

    private let dismissDelay: TimeInterval = 5

    func show(_ message: String, style: ToastStyle = .info) {
        let item = ToastItem(message: message, style: style)
        withAnimation(.easeOut(duration: 0.25)) {
            toasts.append(item)
        }
        Task {
            try? await Task.sleep(for: .seconds(dismissDelay))
            dismiss(item.id)
        }
    }

    func dismiss(_ id: UUID) {
        withAnimation(.easeIn(duration: 0.2)) {
            toasts.removeAll { $0.id == id }
        }
    }
}
