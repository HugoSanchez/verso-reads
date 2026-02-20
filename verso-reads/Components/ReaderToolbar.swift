//
//  ReaderToolbar.swift
//  verso-reads
//

import SwiftUI

struct ReaderToolbar: View {
    let title: String
    let isTitleEditable: Bool
    let onTitleCommit: (String) -> Void
    @Binding var isSidebarVisible: Bool
    let onSidebarToggle: (Bool) -> Void
    @Binding var isRightPanelVisible: Bool
    @Binding var highlightColor: HighlightColor
    let onHighlight: (HighlightColor) -> Void
    let onRightPanelToggle: (Bool) -> Void
    let isZoomEnabled: Bool
    let currentZoomPercent: () -> Double
    let onApplyZoomPercent: (Double) -> Void

    @State private var isEditingTitle = false
    @State private var draftTitle = ""
    @FocusState private var isTitleFocused: Bool
    @State private var isZoomPopoverPresented = false
    @State private var zoomPercent: Double = 100

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.left")
                        .foregroundStyle(isSidebarVisible ? Color.accentColor : Color.black.opacity(0.4))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)

                titleView
                    .padding(.leading, 2)

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
                    Button {
                        isZoomPopoverPresented.toggle()
                    } label: {
                        Text("AA")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .disabled(isZoomEnabled == false)
                    .popover(isPresented: $isZoomPopoverPresented, arrowEdge: .top) {
                        ReaderZoomPopover(
                            zoomPercent: $zoomPercent,
                            isEnabled: isZoomEnabled,
                            zoomRange: 25...400,
                            zoomStep: 10,
                            onApplyZoomPercent: onApplyZoomPercent,
                            onSyncZoomPercent: currentZoomPercent
                        )
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
            .padding(.leading, isSidebarVisible ? 32 : 118)
            .padding(.trailing, 24)
            .padding(.top, 18)
            .padding(.bottom, 14)

            // Subtle separator line
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 1)
                .padding(.horizontal, 24)
        }
        .onChange(of: title) { _, newValue in
            if isEditingTitle == false {
                draftTitle = newValue
            }
        }
    }

    private var titleView: some View {
        Group {
            if isEditingTitle && isTitleEditable {
                TextField("", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .focused($isTitleFocused)
                    .onSubmit { commitTitleEdit() }
                    .onExitCommand { cancelTitleEdit() }
                    .frame(maxWidth: 260, alignment: .leading)
            } else {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .onTapGesture {
                        guard isTitleEditable else { return }
                        beginTitleEdit()
                    }
            }
        }
    }

    private func beginTitleEdit() {
        draftTitle = title
        isEditingTitle = true
        isTitleFocused = true
    }

    private func cancelTitleEdit() {
        isEditingTitle = false
        draftTitle = title
    }

    private func commitTitleEdit() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            cancelTitleEdit()
            return
        }
        isEditingTitle = false
        onTitleCommit(trimmed)
    }

    private func toggleRightPanel() {
        let newValue = !isRightPanelVisible
        onRightPanelToggle(newValue)
        withAnimation(.easeInOut(duration: 0.2)) {
            isRightPanelVisible = newValue
        }
    }

    private func toggleSidebar() {
        let newValue = !isSidebarVisible
        onSidebarToggle(newValue)
        withAnimation(.easeInOut(duration: 0.2)) {
            isSidebarVisible = newValue
        }
    }
}

#Preview {
    ReaderToolbar(
        title: "New reading",
        isTitleEditable: true,
        onTitleCommit: { _ in },
        isSidebarVisible: .constant(true),
        onSidebarToggle: { _ in },
        isRightPanelVisible: .constant(false),
        highlightColor: .constant(.yellow),
        onHighlight: { _ in },
        onRightPanelToggle: { _ in },
        isZoomEnabled: true,
        currentZoomPercent: { 100 },
        onApplyZoomPercent: { _ in }
    )
    .background(Color.white)
}
