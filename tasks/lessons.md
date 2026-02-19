# Lessons

- When refactoring layout, preserve existing visual layers (background fills, padding) unless explicitly agreed; verify diffs for unintended removals.
- Swift 6 concurrency: avoid capturing actor-isolated `self` in nonisolated notification closures; prefer selector-based observers for PDFKit notifications.
