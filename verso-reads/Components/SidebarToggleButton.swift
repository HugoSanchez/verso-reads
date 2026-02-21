//
//  SidebarToggleButton.swift
//  verso-reads
//

import SwiftUI

struct SidebarToggleButton: View {
    let isVisible: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: isVisible ? "sidebar.left" : "sidebar.left")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.6))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SidebarToggleButton(isVisible: true, onToggle: {})
        .padding()
        .background(Color.white)
}
