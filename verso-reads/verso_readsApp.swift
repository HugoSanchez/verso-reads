//
//  verso_readsApp.swift
//  verso-reads
//
//  Created by Hugo Sanchez on 12/2/26.
//

import SwiftUI
import SwiftData

@main
struct verso_readsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(for: [LibraryDocument.self, Annotation.self, DocumentNote.self, ChatMessageRecord.self])
                .onAppear {
                    configureWindow()
                }
        }
        .windowStyle(.hiddenTitleBar)
    }

    private func configureWindow() {
        guard let window = NSApplication.shared.windows.first else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear

        WindowChromeController.shared.attach(to: window)
    }
}

private final class WindowChromeController: NSObject, NSWindowDelegate {
    static let shared = WindowChromeController()

    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []

    func attach(to window: NSWindow) {
        guard self.window !== window else { return }

        self.window = window
        window.delegate = self

        DispatchQueue.main.async { [weak self] in
            self?.positionTrafficLights()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.positionTrafficLights()
        }

        observers.forEach(NotificationCenter.default.removeObserver)
        observers = [
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.positionTrafficLights()
            },
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeMainNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.positionTrafficLights()
            },
            NotificationCenter.default.addObserver(
                forName: NSWindow.didEndLiveResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.positionTrafficLights()
            },
            NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.positionTrafficLights()
            }
        ]
    }

    func windowDidResize(_ notification: Notification) {
        positionTrafficLights()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        positionTrafficLights()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        positionTrafficLights()
    }

    private func positionTrafficLights() {
        guard let window else { return }
        guard let closeButton = window.standardWindowButton(.closeButton) else { return }
        guard let miniButton = window.standardWindowButton(.miniaturizeButton) else { return }
        guard let zoomButton = window.standardWindowButton(.zoomButton) else { return }
        guard let container = closeButton.superview else { return }

        let paddingX: CGFloat = 22
        let paddingY: CGFloat = 18

        let spacing = miniButton.frame.minX - closeButton.frame.maxX
        let y: CGFloat
        if container.isFlipped {
            y = paddingY
        } else {
            y = container.bounds.height - closeButton.frame.height - paddingY
        }

        closeButton.setFrameOrigin(NSPoint(x: paddingX, y: y))
        miniButton.setFrameOrigin(NSPoint(x: paddingX + closeButton.frame.width + spacing, y: y))
        zoomButton.setFrameOrigin(NSPoint(x: paddingX + (closeButton.frame.width + spacing) * 2, y: y))
    }
}
