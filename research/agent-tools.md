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
Create or replace the note for the current document. Overwrites any existing content.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `text` | string | yes | Text content for the note |

**Returns:** `{ "success": true, "action": "created" }`

**Implementation:** Converts text to TipTap JSON (paragraphs split by newlines) and saves to `DocumentNote` via SwiftData.

---

### `append_to_note`
Append text to the end of the user's existing notes. Creates the note if it doesn't exist.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `text` | string | yes | Text content to append |

**Returns:** `{ "success": true, "action": "appended" }`

**Implementation:** Parses existing TipTap JSON, adds a separator paragraph, then appends new paragraphs. Falls back to creating a new note if none exists.

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
