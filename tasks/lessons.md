# Lessons

- Sidebar toggles should not rely on titlebar alignment; prefer an in-sidebar toggle with a floating fallback when hidden to avoid AppKit/SwiftUI alignment issues.
- When refactoring layout, preserve existing visual layers (background fills, padding) unless explicitly agreed; verify diffs for unintended removals.
- Swift 6 concurrency: avoid capturing actor-isolated `self` in nonisolated notification closures; prefer selector-based observers for PDFKit notifications.
- Streaming UI: avoid caching rendered markdown without invalidation; throttle updates, but ensure re-render on each batch so output remains visible.
