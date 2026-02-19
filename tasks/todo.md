# TODO

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
