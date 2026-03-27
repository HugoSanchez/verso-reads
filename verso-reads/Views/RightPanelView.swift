//
//  RightPanelView.swift
//  verso-reads
//

import SwiftUI
import AppKit

struct RightPanelView: View {
    @Binding var chatContext: ChatContext?
    @Binding var messages: [ChatMessage]
    @ObservedObject var settings: OpenAISettingsStore
    @Binding var pinnedPreview: PinnedChatPreview?
    @Binding var activeDocument: LibraryDocument?
    @Binding var isRightPanelVisible: Bool
    let isSidebarVisible: Bool

    @AppStorage("ui.rightPanelWidth.sidebar") private var panelWidthWithSidebar: Double = 360
    @AppStorage("ui.rightPanelWidth.fullWidth") private var panelWidthFullWidth: Double = 400
    @AppStorage("ui.rightPanel.notesRatio") private var notesRatio: Double = 0.5
    @State private var isHoveringSplitHandle = false
    @State private var isHoveringResizeHandle = false

    private let minPanelWidth: Double = 320
    private let maxPanelWidth: Double = 560
    private var panelWidth: Binding<Double> { isSidebarVisible ? $panelWidthWithSidebar : $panelWidthFullWidth }

    var body: some View {
        HStack(spacing: 0) {
            // Vertical divider
            Divider()

            // Panel content
            GeometryReader { geo in
                let headerHeight: CGFloat = 28
                let handleHeight: CGFloat = 9
                let totalFixed = headerHeight * 2 + handleHeight
                let available = max(geo.size.height - totalFixed, 0)
                let notesHeight = available * notesRatio
                let chatHeight = available * (1 - notesRatio)

                VStack(spacing: 0) {
                    // Notes section
                    PanelSectionHeader(title: "Notes")

                    NotepadView()
                        .frame(maxWidth: .infinity)
                        .frame(height: notesHeight)

                    // Draggable split handle
                    ZStack {
                        VerticalSplitHandle(
                            ratio: $notesRatio,
                            isHovering: $isHoveringSplitHandle,
                            availableHeight: available
                        )
                        Divider()
                    }
                    .frame(height: handleHeight)
                    .background(isHoveringSplitHandle ? Color.black.opacity(0.06) : Color.clear)

                    // Chat section
                    PanelSectionHeader(title: "Chat")

                    ChatView(
                        context: $chatContext,
                        messages: $messages,
                        settings: settings,
                        pinnedPreview: $pinnedPreview,
                        activeDocument: $activeDocument,
                        showInput: chatHeight > 120
                    )
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity)
                    .frame(height: chatHeight)
                    .clipped()
                }
            }
        }
        .frame(width: CGFloat(panelWidth.wrappedValue))
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .leading) {
            ZStack(alignment: .leading) {
                RightPanelResizeHandle(
                    width: panelWidth,
                    isHovering: $isHoveringResizeHandle,
                    mode: isSidebarVisible ? 0 : 1,
                    minWidth: minPanelWidth,
                    maxWidth: maxPanelWidth
                )
                .frame(width: 10)

                Rectangle()
                    .fill(isHoveringResizeHandle ? Color.black.opacity(0.06) : Color.clear)
                    .frame(width: 2)
            }
        }
        .onAppear {
            panelWidthWithSidebar = min(max(panelWidthWithSidebar, minPanelWidth), maxPanelWidth)
            panelWidthFullWidth = min(max(panelWidthFullWidth, minPanelWidth), maxPanelWidth)
        }
    }
}

private struct PanelSectionHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.5))

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct VerticalSplitHandle: NSViewRepresentable {
    @Binding var ratio: Double
    @Binding var isHovering: Bool
    let availableHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(ratio: $ratio, isHovering: $isHovering, availableHeight: availableHeight)
    }

    func makeNSView(context: Context) -> SplitHandleView {
        let view = SplitHandleView()
        view.onHoverChanged = { hovering in
            context.coordinator.isHovering.wrappedValue = hovering
        }
        view.onDragChanged = { deltaY in
            context.coordinator.apply(deltaY: deltaY)
        }
        view.onDragEnded = {
            context.coordinator.endDrag()
        }
        return view
    }

    func updateNSView(_ nsView: SplitHandleView, context: Context) {
        context.coordinator.ratio = $ratio
        context.coordinator.isHovering = $isHovering
        context.coordinator.availableHeight = availableHeight
    }

    final class Coordinator {
        var ratio: Binding<Double>
        var isHovering: Binding<Bool>
        var availableHeight: CGFloat
        var startRatio: Double?

        init(ratio: Binding<Double>, isHovering: Binding<Bool>, availableHeight: CGFloat) {
            self.ratio = ratio
            self.isHovering = isHovering
            self.availableHeight = availableHeight
        }

        func apply(deltaY: CGFloat) {
            if startRatio == nil { startRatio = ratio.wrappedValue }
            guard availableHeight > 0 else { return }
            let delta = Double(deltaY) / Double(availableHeight)
            let proposed = (startRatio ?? ratio.wrappedValue) - delta
            ratio.wrappedValue = min(max(proposed, 0.0), 1.0)
        }

        func endDrag() {
            startRatio = nil
        }
    }

    final class SplitHandleView: NSView {
        var onHoverChanged: ((Bool) -> Void)?
        var onDragChanged: ((CGFloat) -> Void)?
        var onDragEnded: (() -> Void)?

        private var trackingArea: NSTrackingArea?
        private var isDragging = false
        private var startYInWindow: CGFloat = 0

        override var mouseDownCanMoveWindow: Bool { false }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea { removeTrackingArea(trackingArea) }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeUpDown)
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            onHoverChanged?(true)
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            if !isDragging { onHoverChanged?(false) }
        }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            isDragging = true
            startYInWindow = event.locationInWindow.y
        }

        override func mouseDragged(with event: NSEvent) {
            super.mouseDragged(with: event)
            let deltaY = event.locationInWindow.y - startYInWindow
            onDragChanged?(deltaY)
        }

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            isDragging = false
            onDragEnded?()
            let inside = bounds.contains(convert(event.locationInWindow, from: nil))
            onHoverChanged?(inside)
        }
    }
}

private struct RightPanelResizeHandle: NSViewRepresentable {
    @Binding var width: Double
    @Binding var isHovering: Bool
    let mode: Int
    let minWidth: Double
    let maxWidth: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(width: $width, isHovering: $isHovering, mode: mode, minWidth: minWidth, maxWidth: maxWidth)
    }

    func makeNSView(context: Context) -> ResizeHandleView {
        let view = ResizeHandleView()
        view.onHoverChanged = { hovering in
            context.coordinator.isHovering.wrappedValue = hovering
        }
        view.onDragChanged = { deltaX in
            context.coordinator.apply(deltaX: deltaX)
        }
        view.onDragEnded = {
            context.coordinator.endDrag()
        }
        return view
    }

    func updateNSView(_ nsView: ResizeHandleView, context: Context) {
        context.coordinator.width = $width
        context.coordinator.isHovering = $isHovering
        if context.coordinator.mode != mode {
            context.coordinator.mode = mode
            context.coordinator.endDrag()
        }
    }

    final class Coordinator: NSObject {
        var width: Binding<Double>
        var isHovering: Binding<Bool>
        var mode: Int
        let minWidth: Double
        let maxWidth: Double
        var startWidth: Double?

        init(width: Binding<Double>, isHovering: Binding<Bool>, mode: Int, minWidth: Double, maxWidth: Double) {
            self.width = width
            self.isHovering = isHovering
            self.mode = mode
            self.minWidth = minWidth
            self.maxWidth = maxWidth
        }

        func apply(deltaX: CGFloat) {
            if startWidth == nil {
                startWidth = width.wrappedValue
            }

            let start = startWidth ?? width.wrappedValue
            let proposed = start - Double(deltaX)
            width.wrappedValue = min(max(proposed, minWidth), maxWidth)
        }

        func endDrag() {
            startWidth = nil
        }
    }

    final class ResizeHandleView: NSView {
        var onHoverChanged: ((Bool) -> Void)?
        var onDragChanged: ((CGFloat) -> Void)?
        var onDragEnded: (() -> Void)?

        private var trackingArea: NSTrackingArea?
        private var isDragging = false
        private var startXInWindow: CGFloat = 0

        override var mouseDownCanMoveWindow: Bool { false }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            onHoverChanged?(true)
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            if isDragging == false {
                onHoverChanged?(false)
            }
        }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            isDragging = true
            startXInWindow = event.locationInWindow.x
        }

        override func mouseDragged(with event: NSEvent) {
            super.mouseDragged(with: event)
            let deltaX = event.locationInWindow.x - startXInWindow
            onDragChanged?(deltaX)
        }

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            isDragging = false
            onDragEnded?()

            let inside = bounds.contains(convert(event.locationInWindow, from: nil))
            onHoverChanged?(inside)
        }
    }
}

#Preview {
    HStack(spacing: 0) {
        Color.gray.opacity(0.1)
        RightPanelView(
            chatContext: .constant(nil),
            messages: .constant([]),
            settings: OpenAISettingsStore(),
            pinnedPreview: .constant(nil),
            activeDocument: .constant(nil),
            isRightPanelVisible: .constant(true),
            isSidebarVisible: true
        )
    }
    .frame(width: 800, height: 600)
    .environmentObject(ReaderSession())
}
