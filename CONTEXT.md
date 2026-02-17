# Context

## What We Are Building

- A native macOS reading app (SwiftUI) focused on a calm, distraction-free reading experience.
- Another way to put it is that we are building a "Cursor for reading".
- We want to make it such that people get the most out of their reads and multiply their reading/learing/research productivity in a way that feels natural and calm.
- Core UI: a translucent sidebar plus a clean white reading canvas, inspired by the Codex aesthetic.
- Future goals: PDF rendering, library/collections, highlights, notes, and synced reading position.
- We want to allow users to RAG their documents locally.
- Ask questions about the text to LLMs inside the app and pin some of their answers to the text.
- Link notes and subjects between them.
- etc.

## How We Want It Built

- Follow SwiftUI best practices with clean, reusable components.
- Keep views small and composable; avoid giant view files.
- Prefer clear naming and logical folder structure (e.g., `Views/`, `Models/`, `Services/`, `Resources/`).
- Minimize global state; use `@State`, `@StateObject`, and `@EnvironmentObject` intentionally.
- Isolate platform-specific code where needed (e.g., `PDFKit` wrappers).
- Aim for performance and maintainability over quick hacks.

## Last Work + Current State

### Session 2 (Feb 13, 2026)
- **PDF Rendering**: Added ability to open and view PDF documents via drag-and-drop or click-to-open.
- **PDFKitView**: Created `PDFKitView` wrapper for PDFKit with customized appearance (no shadows, subtle page gaps).
- **Codebase Refactor**: Reorganized into clean component structure following best practices:
  - `Views/`: `SidebarView`, `ReaderCanvasView`, `RightPanelView`, `NotepadView`, `ChatView`
  - `Components/`: `SidebarRow`, `ReaderToolbar`, `EmptyReaderState`, `PDFKitView`
- **Right Panel**: Split into two sections - Notes (top) and Chat (bottom) with placeholder content.
- **EmptyReaderState**: Interactive empty state with tap-to-open and drag-and-drop support.

### Session 1
- Built a first-pass layout: translucent sidebar + connected main canvas.
- Removed outer padding so sidebar and canvas are joined in a single container.
- Added a unified top bar to match the Codex-style window header.
- Implemented a custom right-corner rounding shape for the main canvas (macOS-safe).

### Current File Structure
```
verso-reads/
├── ContentView.swift          # Main layout composer
├── verso_readsApp.swift       # App entry point
├── Views/
│   ├── SidebarView.swift      # Left sidebar with navigation
│   ├── ReaderCanvasView.swift # PDF viewer or empty state
│   ├── RightPanelView.swift   # Notes + Chat panel
│   ├── NotepadView.swift      # Notes section (placeholder)
│   └── ChatView.swift         # Chat section with input
└── Components/
    ├── SidebarRow.swift       # Reusable sidebar row
    ├── ReaderToolbar.swift    # Reader header with actions
    ├── EmptyReaderState.swift # Drop/click to open PDF
    └── PDFKitView.swift       # PDFKit wrapper
```
