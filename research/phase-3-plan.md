# Phase 3: Cross-Document Intelligence — Implementation Plan

## Goal
Give the agent awareness beyond the current document — search across the library, list documents/collections, and read past chat history.

## New Tools

### 1. `search_all_documents`
Search across ALL documents in the user's library using RAG vector search.

**Parameters:** `query` (string, required)
**Returns:** Array of results with `documentTitle`, `documentID`, `page`, `text`, `distance`

**Implementation:**
- Add `searchSimilarAll(embeddingJSON:limit:)` to `RAGStore` — same SQL but without the `AND document_id = ?` filter
- Add `retrieveContextAll(query:apiKey:)` to `RAGQueryService` — calls the new RAGStore method
- Add tool definition + executor case
- Results should include the document title so the agent can say "In your paper X, I found..."

**Key SQL change in RAGStore:**
```sql
-- Current (single doc):
SELECT ... WHERE embedding MATCH ? AND k = ? AND document_id = ?

-- New (all docs):
SELECT re.*, rd.title as document_title
FROM rag_embeddings re
JOIN rag_documents rd ON re.document_id = rd.document_id
WHERE re.embedding MATCH ? AND k = ?
```

---

### 2. `get_library`
List all documents in the user's library.

**Parameters:** none
**Returns:** Array of `{ id, title, filename, pageCount, lastOpenedAt }`

**Implementation:**
- Fetch all `LibraryDocument` from SwiftData
- Sort by `lastOpenedAt` descending
- Limit to 50 documents to avoid token bloat
- Include basic metadata only (no content)

---

### 3. `get_collections`
List all document collections and their members.

**Parameters:** none
**Returns:** Array of `{ id, name, documents: [{ id, title }] }`

**Implementation:**
- Fetch all `DocumentCollection` from SwiftData
- For each, resolve `documentIDs` to titles via `LibraryDocument` lookup
- Already have `DocumentCollection` model with `documentIDs: [UUID]`

---

### 4. `get_chat_history`
Read past chat conversations about a specific document.

**Parameters:** `document_id` (string, optional — defaults to current document)
**Returns:** Array of `{ role, content, createdAt }` (last 30 messages)

**Implementation:**
- Fetch `ChatMessageRecord` filtered by documentID
- Sort by `createdAt`
- Limit to last 30 messages
- If no `document_id` param, use current document

---

## Files to Modify

| File | Change |
|------|--------|
| `RAGStore.swift` | Add `searchSimilarAll()` method |
| `RAGQueryService.swift` | Add `retrieveContextAll()` method |
| `ToolDefinition.swift` | Add 4 new tool schemas |
| `ToolExecutor.swift` | Add 4 new executor cases |
| `AgentLoop.swift` | Update system prompt with cross-doc guidance |
| `ChatView.swift` | Update `toolStatusText()` |
| `research/agent-tools.md` | Document new tools |

## Order of Implementation

1. **`get_library`** — simplest, no RAG changes, immediate value
2. **`get_collections`** — same pattern, trivial after #1
3. **`get_chat_history`** — straightforward SwiftData query
4. **`search_all_documents`** — hardest, requires RAGStore SQL change

## System Prompt Updates

Add guidance like:
- "You can search across the user's entire library with `search_all_documents`. Use this when the user asks about connections between documents or wants to find something they read before."
- "Use `get_library` to see what documents the user has. Use `get_collections` to understand how they've organized their reading."
- "Use `get_chat_history` to recall previous conversations about a document."

## Testing Plan

- **`get_library`**: "What documents do I have?" — should list titles
- **`get_collections`**: "What are my collections?" — should list collections with doc names
- **`get_chat_history`**: "What did we talk about last time?" — should recall prior messages
- **`search_all_documents`**: "Which of my papers mentions attention mechanisms?" — should find results across multiple documents
- **Cross-tool chain**: "Find all mentions of X across my library and highlight them in the current document" — chains `search_all_documents` → `get_page_text` → `create_highlight`
