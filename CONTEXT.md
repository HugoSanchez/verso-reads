# Context

## What We Are Building
- A native macOS reading app (SwiftUI) focused on a calm, distraction-free reading experience.
- Core UI: a translucent sidebar plus a clean white reading canvas, inspired by the Codex aesthetic.
- Future goals: PDF rendering, library/collections, highlights, notes, and synced reading position.

## How We Want It Built
- Follow SwiftUI best practices with clean, reusable components.
- Keep views small and composable; avoid giant view files.
- Prefer clear naming and logical folder structure (e.g., `Views/`, `Models/`, `Services/`, `Resources/`).
- Minimize global state; use `@State`, `@StateObject`, and `@EnvironmentObject` intentionally.
- Isolate platform-specific code where needed (e.g., `PDFKit` wrappers).
- Aim for performance and maintainability over quick hacks.

## Last Work + Current State
- Built a first-pass layout: translucent sidebar + connected main canvas.
- Removed outer padding so sidebar and canvas are joined in a single container.
- Added a unified top bar to match the Codex-style window header.
- Implemented a custom right-corner rounding shape for the main canvas (macOS-safe).
- Current layout lives in `verso-reads/ContentView.swift`.
