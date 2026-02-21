# TODO

## Next: Reader Header (Toolbar / Titlebar)

- [ ] Plan: decide toolbar vs titlebar integration approach.
- [ ] Implement Option 2: SwiftUI `.toolbar` for reader header.
- [ ] Ensure Settings view remains unchanged.
- [ ] Verify alignment with traffic lights and spacing.

## Review (Reader Header)

- [ ] Verify reader header aligns with traffic lights.
- [ ] Verify sidebar toggle and right panel still work.

## Next: Sidebar Toggle (Floating)

- [x] Add reusable sidebar toggle button component.
- [ ] Decide final toggle placement (header vs sidebar vs none).

## Next: Notes (WYSIWYG WebView)

- [x] Embed WKWebView with TipTap editor (no toolbar).
- [x] Match chat font sizing and add placeholder.
- [ ] Decide persistence + markdown export strategy.
- [ ] Add quote insertion + anchors (later).

## Review (Notes WebView)

- [ ] Verify editor loads and accepts typing.
- [ ] Verify placeholder and basic formatting shortcuts.

- [x] Add a lightweight Settings screen rendered in the main reader area when the sidebar gear is selected.
- [x] Implement Keychain storage for the user’s OpenAI API key (local‑only), plus a simple model picker defaulting to `gpt-5.2`.
- [x] Build an `OpenAIClient` service using the Responses API with SSE streaming (`stream=true`) over URLSession.
- [x] Parse streaming events and progressively append assistant output into the chat UI.
- [x] Wire ChatView to send: system prompt + selected‑text context + user question.
- [x] Add UX guards: disable send if API key missing; show a prompt to add key in Settings.
- [x] Keep request building modular to enable future RAG/tools (inputs/tools injection).

## Review

- [ ] Verify Settings renders in the reader area and saves/reloads the API key from Keychain.
- [ ] Verify streaming output renders progressively in chat.

## Next: Markdown + Chat Input

- [x] Decide markdown rendering approach (MarkdownUI) and define shared styling.
- [x] Add a reusable Markdown view for both Chat and Notes.
- [x] Render markdown during streaming with throttled re-renders.
- [x] Implement Enter-to-send in chat input (Shift+Enter for newline).

## Review (Markdown + Input)

- [ ] Verify markdown renders correctly in chat.
- [ ] Verify Enter sends and Shift+Enter inserts newline.

## Next: RAG (MVP Ingestion + Retrieval)

- [ ] Confirm `sqlite-vec` as the vector extension and decide how to bundle it for macOS.
- [ ] Define schema for docs/chunks/embeddings using `sqlite-vec` tables and migration strategy.
- [ ] Build ingestion pipeline scaffolding (extract text -> chunk -> persist chunks).
- [ ] Integrate OpenAI embeddings and store vectors; ensure idempotent re-indexing.
- [ ] Implement retrieval path (embed query -> kNN search -> assemble context).
- [ ] Add UI feedback for indexing state + error surfacing.

## Review (RAG MVP)

- [ ] Verify a new document triggers ingestion.
- [ ] Verify embeddings are stored and retrievable.
- [ ] Verify chat queries use retrieved context.
