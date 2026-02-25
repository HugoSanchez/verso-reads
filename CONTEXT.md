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

## Workflow Orchestration

### 1. Plan Mode Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately — don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### 2. Subagent Strategy
- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One task per subagent for focused execution

### 3. Self-Improvement Loop
- After ANY correction from the user: update `tasks/lessons.md` with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for relevant project

### 4. Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### 5. Demand Elegance (Balanced)
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes — don't over-engineer
- Challenge your own work before presenting it

### 6. Autonomous Bug Fixing
- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests — then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how

## Task Management

1. **Plan First**: Write plan to `tasks/todo.md` with checkable items
2. **Verify Plan**: Check in before starting implementation
3. **Track Progress**: Mark items complete as you go
4. **Explain Changes**: High-level summary at each step
5. **Document Results**: Add review section to `tasks/todo.md`
6. **Capture Lessons**: Update `tasks/lessons.md` after corrections

## Core Principles

- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimal Impact**: Changes should only touch what's necessary. Avoid introducing bugs.

## Known Issues (Track Later)

- **WebContent pasteboard sandbox**: `Failed to set up CFPasteboardRef 'general'` / `Sandbox restriction` errors in WebContent; may affect copy/paste in notes WebView.
- **LaunchServices lookup denied**: WebContent cannot register with `launchservicesd` / `coreservicesd` due to sandbox restrictions; could affect link handling.
- **RunningBoard / intents entitlements**: missing entitlements for intents framework; currently benign but noted.
- **AudioComponentRegistrar denied**: sandbox blocks audio registrar; likely benign unless WebContent needs audio.
- **WebContent XPC / TCC warnings**: `XPC_ERROR_CONNECTION_INVALID` / `TCCAccessRequest_block_invoke` from WebContent talking to system services (LaunchServices/TCC) under sandbox; typically benign unless link handling or permissions are broken.
- **IconRendering metallib warning**: `unable to load binary archive for shader library ... IconRendering.framework ... binary.metallib` appears in some environments; treat as system noise unless icon rendering breaks.

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
