//
//  ContentView.swift
//  verso-reads
//
//  Created by Hugo Sanchez on 12/2/26.
//

import SwiftUI

struct ContentView: View {
    @State private var isRightPanelVisible = false

    private let sidebarWidth: CGFloat = 220

    var body: some View {
        ZStack(alignment: .leading) {
            // Sidebar underneath
            SidebarView()
                .frame(maxHeight: .infinity)

            // Background fill for the rounded corner gaps (matches sidebar color)
            Color.white.opacity(0.55)
                .padding(.leading, sidebarWidth)

            // Main content area with optional right panel
            HStack(spacing: 0) {
                // Reader canvas
                ReaderCanvasView(isRightPanelVisible: $isRightPanelVisible)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 12,
                            bottomLeadingRadius: 12,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0
                        )
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.1), radius: 6, x: -2, y: 0)
                    )

                // Right panel (Chat/Notes)
                if isRightPanelVisible {
                    RightPanelView()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.leading, sidebarWidth)
        }
        .ignoresSafeArea()
        .background(.ultraThinMaterial)
    }
}

#Preview {
    ContentView()
        .frame(width: 1200, height: 760)
}
