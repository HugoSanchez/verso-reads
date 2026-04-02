# Verso Reads — Agent Tools Reference

All tools available to the AI reading assistant. Tools are defined in `ToolDefinition.swift` and executed in `ToolExecutor.swift`.

---

## Read Tools (Phase 1)

### `search_document`
Search the current document for passages relevant to a query using RAG (vector similarity search).

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `query` | string | yes | Natural language search query |

**Returns:** Relevant passages from the document with page references.

---

### `read_highlights`
Fetch all highlights the user has made on the current document.

No parameters.

**Returns:** JSON array of highlights, each with `id`, `quote`, `color`, and `page`.

---

### `read_notes`
Fetch the user's notepad content for the current document.

No parameters.

**Returns:** Plain text extracted from the TipTap JSON note content.

---

### `get_document_info`
Get metadata about the current document.

No parameters.

**Returns:** JSON with `title`, `filename`, `fileType`, `pageCount`, and optionally `author` and `subject` (from PDF metadata).

---

### `get_current_page`
Get the page number the user is currently viewing.

No parameters.

**Returns:** `{ "currentPage": N }` (1-based page number).

---

### `get_page_text`
Extract the full text content of a specific page.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `page` | number | yes | Page number (1-based) |

**Returns:** Raw text content of the page.

---

## Write Tools (Phase 2)

### `navigate_to_page`
Scroll the document view to a specific page.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `page` | number | yes | Page number to navigate to (1-based) |

**Returns:** `{ "success": true, "navigatedTo": N }`

**Implementation:** Sets `ReaderSession.pendingPageNavigation`, which `ReaderCanvasView` observes to call `pdfView.go(to:)`.

---

### `create_note`
Create a new note for the current document. Fails if a note already exists (agent should use `append_to_note` instead).

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `text` | string | yes | Text content for the note |

**Returns:** `{ "success": true, "action": "created" }` or error if note exists.

**Implementation:** Sets `ReaderSession.pendingNoteAppend`, which NotepadView observes and forwards to TipTap's `VersoNotesAppendText` JS function using `insertContentAt`.

---

### `append_to_note`
Append text to the end of the user's existing notes. Creates the note if it doesn't exist.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `text` | string | yes | Text content to append |

**Returns:** `{ "success": true, "action": "appended" }`

**Implementation:** Sets `ReaderSession.pendingNoteAppend`, which NotepadView observes and forwards to TipTap's `VersoNotesAppendText` JS function using `insertContentAt`. TipTap handles persistence through its normal `onUpdate` → `scheduleContentPost` flow.

---

## Planned Tools (Not Yet Implemented)

### Phase 2 — Highlight Tools
- `create_highlight` — Highlight text in the PDF (requires PDFTextMatcher for text→coordinate mapping)
- `delete_highlight` — Remove a highlight by ID
- `update_highlight` — Change highlight color

### Phase 3 — Cross-Document Intelligence
- `search_all_documents` — RAG search across the entire library
- `get_library` / `get_collections` — List documents in the user's library
- `get_chat_history` — Retrieve past chat conversations

### Phase 4 — External Research
- `search_arxiv` — Search arXiv for papers
- `search_semantic_scholar` — Search Semantic Scholar

---

## Architecture

```
ChatView
  └─ AgentLoop (max 10 iterations)
       ├─ OpenAIClient.streamAgentResponse()  ← SSE streaming
       ├─ ToolExecutor.execute(name, args)     ← dispatches to tool
       └─ Continues with previous_response_id  ← multi-turn tool use
```

- **Tool definitions** live in `ToolDefinition.swift` as `AgentTools.all`
- **Tool execution** lives in `ToolExecutor.swift` (runs `@MainActor`)
- **Agent loop** lives in `AgentLoop.swift` using the ReAct pattern
- **System prompt** is built by `AgentLoop.buildSystemPrompt(documentTitle:)` and includes guidance on when to use each tool
