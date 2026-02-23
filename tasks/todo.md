# TODO

## Next: Reader Header (Toolbar / Titlebar)

- [x] Plan: decide toolbar vs titlebar integration approach.
- [x] Implement Option 2: SwiftUI `.toolbar` for reader header.
- [x] Ensure Settings view remains unchanged.
- [x] Verify alignment with traffic lights and spacing.

## Review (Reader Header)

- [x] Verify reader header aligns with traffic lights.
- [x] Verify sidebar toggle and right panel still work.

## Next: Sidebar Toggle (Floating)

- [x] Add reusable sidebar toggle button component.
- [x] Decide final toggle placement (header vs sidebar vs none).

## Next: Notes (WYSIWYG WebView)

- [x] Embed WKWebView with TipTap editor (no toolbar).
- [x] Match chat font sizing and add placeholder.
- [x] Decide persistence + markdown export strategy.
- [x] Add quote insertion + anchors (later).

## Review (Notes WebView)

- [x] Verify editor loads and accepts typing.
- [x] Verify placeholder and basic formatting shortcuts.

## Plan: Notes Persistence (Markdown Autosave)

- [x] Add SwiftData model for per-document notes.
- [x] Wire NotesWebView <-> Swift bridge for markdown autosave (debounced).
- [x] Load saved markdown on editor init and set content.
- [ ] Verify autosave on typing and reload on app restart.

## Plan: Notes Offline Editor (Step 1)

- [x] Inventory current NotesWebView setup and identify external dependencies.
- [x] Build a local TipTap bundle (core + starter-kit + placeholder) and save as `Resources/NotesEditor/tiptap.bundle.js`.
- [x] Add `Resources/NotesEditor/index.html` that loads the local bundle and initializes the editor.
- [ ] Add Notes editor resources to the Xcode target (Copy Bundle Resources).
- [x] Update `NotesWebView` to load the bundled HTML via `loadFileURL` and set `baseURL` for local assets.
- [x] Add a short build note (versions + how to rebuild) in `Resources/NotesEditor/README.md` or a comment in `NotesWebView`.
- [ ] Verify editor loads with Wi-Fi disabled (basic typing + placeholder).
- [ ] Decide whether to keep inline HTML fallback or require bundled resources only.
- [ ] Investigate WKWebView focus/typing issue if fallback still doesn't accept input.

- [x] Add a lightweight Settings screen rendered in the main reader area when the sidebar gear is selected.
- [x] Implement Keychain storage for the user’s OpenAI API key (local‑only), plus a simple model picker defaulting to `gpt-5.2`.
- [x] Build an `OpenAIClient` service using the Responses API with SSE streaming (`stream=true`) over URLSession.
- [x] Parse streaming events and progressively append assistant output into the chat UI.
- [x] Wire ChatView to send: system prompt + selected‑text context + user question.
- [x] Add UX guards: disable send if API key missing; show a prompt to add key in Settings.
- [x] Keep request building modular to enable future RAG/tools (inputs/tools injection).

## Review

- [x] Verify Settings renders in the reader area and saves/reloads the API key from Keychain.
- [x] Verify streaming output renders progressively in chat.

## Next: Markdown + Chat Input

- [x] Decide markdown rendering approach (MarkdownUI) and define shared styling.
- [x] Add a reusable Markdown view for both Chat and Notes.
- [x] Render markdown during streaming with throttled re-renders.
- [x] Implement Enter-to-send in chat input (Shift+Enter for newline).

## Review (Markdown + Input)

- [x] Verify markdown renders correctly in chat.
- [x] Verify Enter sends and Shift+Enter inserts newline.

## Next: Chat Persistence

- [x] Add SwiftData models for chat messages tied to documents.
- [x] Persist user + assistant messages on send/finish.
- [x] Include recent chat history in each request (no auto-load yet).

## Review (Chat Persistence)

- [ ] Verify messages are written to the database.
- [ ] Verify follow-up questions include prior context in the same session.

## Next: RAG (MVP Ingestion + Retrieval)

- [ ] Confirm `sqlite-vec` as the vector extension and decide how to bundle it for macOS.
- [ ] Define schema for docs/chunks/embeddings using `sqlite-vec` tables and migration strategy.
- [ ] Build ingestion pipeline scaffolding (extract text -> chunk -> persist chunks).
- [ ] Integrate OpenAI embeddings and store vectors; ensure idempotent re-indexing.
- [ ] Implement retrieval path (embed query -> kNN search -> assemble context).
- [ ] Add UI feedback for indexing state + error surfacing.

## Plan: RAG (sqlite-vec)

- [ ] Add sqlite-vec loader + DB path helper in Services.
- [ ] Create RAG schema (docs, chunks, vec table) and migration/bootstrapping.
- [ ] Implement text extraction + chunker + ingestion pipeline triggered on import.
- [ ] Add OpenAI embeddings request + persistence; reindex guard.
- [ ] Wire retrieval into chat (query embedding -> vec search -> context).
- [ ] Add basic indexing status and error plumbing.

## Review (RAG MVP)

- [ ] Verify a new document triggers ingestion.
- [ ] Verify embeddings are stored and retrievable.
- [ ] Verify chat queries use retrieved context.
