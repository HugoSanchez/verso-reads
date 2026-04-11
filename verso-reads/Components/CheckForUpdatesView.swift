import SwiftUI
import Sparkle

struct CheckForUpdatesView: View {
    let updater: SPUUpdater

    @State private var canCheckForUpdates = false

    var body: some View {
        Button("Check for Updates...") {
            updater.checkForUpdates()
        }
        .disabled(!canCheckForUpdates)
        .onReceive(updater.publisher(for: \.canCheckForUpdates)) { value in
            canCheckForUpdates = value
        }
    }
}
