//
//  verso_readsApp.swift
//  verso-reads
//
//  Created by Hugo Sanchez on 12/2/26.
//

import SwiftUI

@main
struct verso_readsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
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
    }
}
