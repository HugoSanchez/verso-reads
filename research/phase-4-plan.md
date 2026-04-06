# Phase 4: External Research — Implementation Plan

## Goal
Give the agent the ability to search for academic papers on the web and, when asked, download them directly into the user's library. This turns Verso Reads from a tool that only works with what the user already has into one that actively helps them discover and collect new reading material.

## New Tools (5 total)

### 1. `search_arxiv`
Search arXiv for papers matching a query. Returns metadata only (no PDF download).

**Parameters:** `query` (string, required), `max_results` (number, optional, default 5)
**Returns:** Array of `{ arxiv_id, title, authors, abstract, published, pdf_url }`

**Implementation:**
- Create `ArxivClient.swift` — a lightweight HTTP client for the arXiv API
- Endpoint: `GET http://export.arxiv.org/api/query?search_query=all:{query}&max_results={n}`
- Response is Atom XML — parse with `XMLParser` or `Foundation.XMLDocument`
- Extract: `<entry>` → `<id>`, `<title>`, `<author><name>`, `<summary>`, `<published>`, `<link rel="related" type="application/pdf">`
- Rate limit: respect 3-second minimum between requests (enforce via `actor` with timestamp tracking)
- No API key needed

**Key decisions:**
- Map arXiv search query syntax: `all:` searches title + abstract + full text
- Truncate abstracts to ~300 chars to avoid token bloat
- Return the `pdf_url` so `download_paper` can use it directly

---

### 2. `search_semantic_scholar`
Search Semantic Scholar for papers. Richer metadata than arXiv (citation counts, venue, open access status).

**Parameters:** `query` (string, required), `max_results` (number, optional, default 5)
**Returns:** Array of `{ paper_id, title, authors, abstract, year, citation_count, venue, pdf_url? }`

**Implementation:**
- Create `SemanticScholarClient.swift` — HTTP client for the S2 API
- Endpoint: `GET https://api.semanticscholar.org/graph/v1/paper/search?query={query}&limit={n}&fields=title,authors,abstract,year,citationCount,venue,openAccessPdf`
- Response is JSON — straightforward `Codable` parsing
- `openAccessPdf.url` may be `null` for paywalled papers — include it when available
- Rate limit: 5,000 requests per 5 minutes (unauthenticated) — more than enough
- No API key needed (optional for higher limits)

**Key decisions:**
- Truncate abstracts to ~300 chars
- Include `citation_count` — helps the agent recommend the most impactful papers
- When `pdf_url` is null, the agent should tell the user the paper isn't freely available

---

### 3. `download_paper`
Download a PDF from a URL and import it into the user's library.

**Parameters:**
- `url` (string, required) — the PDF URL to download
- `title` (string, required) — the paper title (used as the document title)
- `collection_id` (string, optional) — UUID of a collection to add the paper to

**Returns:** `{ success, document_id, title }` or `{ error }`

**Implementation:**
- Validate the URL (must be HTTPS, must end in `.pdf` or come from a known domain like `arxiv.org`)
- Download via `URLSession.shared.data(from: url)` with a timeout of 30 seconds
- Write the PDF to a temporary file
- Call `LibraryStore.importDocument(from: tempURL, modelContext:)` to import into the library
- If `collection_id` is provided, fetch the `DocumentCollection` and call `addDocument(docID)`
- Trigger RAG ingestion: `RAGIngestionManager.shared.enqueue(document:fileURL:)`
- Clean up the temp file
- Return the new document's ID so the agent can reference it

**Key decisions:**
- This is a high-trust action — the system prompt should instruct the agent to confirm with the user before downloading ("I found this paper: [title]. Want me to add it to your library?")
- URL validation is important — only allow HTTPS and known academic domains (arxiv.org, semanticscholar.org, openreview.net, etc.) to avoid downloading arbitrary files
- Set a reasonable max file size (50MB) to prevent abuse
- The title param lets us give the document a clean name instead of "document.pdf"

---

### 4. `add_to_collection`
Add an existing document to a collection. Complements `download_paper` for organizing after import.

**Parameters:**
- `document_id` (string, required) — UUID of the document
- `collection_name` (string, required) — name of the collection (created if it doesn't exist)

**Returns:** `{ success, collection_id, collection_name }`

**Implementation:**
- Fetch all `DocumentCollection` from SwiftData
- Find by name (case-insensitive match), or create a new one if not found
- Call `collection.addDocument(documentID)` (already handles dedup)
- Save context

**Key decisions:**
- Match by name rather than ID — more natural for the agent to say "add to my ML papers collection"
- Create-if-not-exists behavior makes it seamless ("add this to 'Attention Papers'" just works even if the collection doesn't exist yet)

---

### 5. `web_search` (optional / future consideration)
Use OpenAI's built-in `web_search` tool for general web queries.

**Status:** Defer to Phase 5. The arXiv + Semantic Scholar tools cover the academic use case well. General web search adds complexity (requires OpenAI Responses API `web_search` tool type, different from function calls) and is less focused on the reading assistant use case.

---

## Files to Create

| File | Purpose |
|------|---------|
| `ArxivClient.swift` | HTTP client + XML parser for arXiv API |
| `SemanticScholarClient.swift` | HTTP client + Codable models for S2 API |

## Files to Modify

| File | Change |
|------|--------|
| `ToolDefinition.swift` | Add 4 new tool schemas (`search_arxiv`, `search_semantic_scholar`, `download_paper`, `add_to_collection`) |
| `ToolExecutor.swift` | Add 4 new executor cases + implementation methods |
| `AgentLoop.swift` | Update system prompt with external research guidance |
| `ChatView.swift` | Add 4 new `toolStatusText()` entries |
| `LibraryStore.swift` | Add `importFromURL(url:title:modelContext:)` method for downloading + importing in one step |

## Order of Implementation

### Step 1: `ArxivClient.swift`
Create the arXiv HTTP client with XML parsing. This is self-contained with no dependencies on existing code.

```
ArxivClient.swift
├── struct ArxivPaper (id, title, authors, abstract, published, pdfURL)
├── func search(query:maxResults:) async throws -> [ArxivPaper]
└── private func parseAtomFeed(data:) -> [ArxivPaper]
```

### Step 2: `SemanticScholarClient.swift`
Create the Semantic Scholar HTTP client with Codable parsing. Also self-contained.

```
SemanticScholarClient.swift
├── struct S2Paper (paperId, title, authors, abstract, year, citationCount, venue, pdfURL)
├── struct S2SearchResponse: Codable
└── func search(query:maxResults:) async throws -> [S2Paper]
```

### Step 3: Tool definitions + search executors
Add `search_arxiv` and `search_semantic_scholar` to `ToolDefinition.swift` and `ToolExecutor.swift`. These are read-only and low-risk — good to ship and test before the write tools.

### Step 4: `download_paper` tool
Add the download tool. Requires:
- URL validation logic
- Temp file download via URLSession
- Integration with `LibraryStore.importDocument`
- RAG ingestion trigger
- Optional collection assignment

### Step 5: `add_to_collection` tool
Simple SwiftData tool. Fetch-or-create collection, add document.

### Step 6: System prompt + status text
Update `AgentLoop.buildSystemPrompt()` with guidance for all 4 tools. Update `ChatView.toolStatusText()`.

## System Prompt Additions

```
- search_arxiv: When the user asks to find academic papers, search for related work, or wants to know what's been published on a topic. Returns paper metadata and abstracts.
- search_semantic_scholar: Similar to search_arxiv but includes citation counts and venue info. Prefer this when the user cares about paper impact or wants the most-cited work.
- download_paper: When the user asks to download, save, or add a paper to their library. IMPORTANT: Always confirm with the user before downloading. Tell them the paper title and ask if they want to add it.
- add_to_collection: When the user asks to organize a document into a collection. Creates the collection if it doesn't exist.
```

## Safety Considerations

### URL validation for `download_paper`
Only allow downloads from known academic sources:
- `arxiv.org`
- `semanticscholar.org`
- `openreview.net`
- `aclanthology.org`
- `proceedings.neurips.cc`
- `proceedings.mlr.press`

This allowlist prevents the agent from downloading arbitrary files from the internet. Can be expanded later.

### File size limit
Cap downloads at 50MB. Most papers are 1-5MB. Anything larger is likely not a paper.

### User confirmation
The system prompt should instruct the agent to always ask before downloading. The agent should present the paper title, authors, and a brief description, then ask "Want me to add this to your library?"

## Testing Plan

1. **`search_arxiv`**: "Find recent papers about retrieval augmented generation" — should return 5 papers with titles, authors, abstracts
2. **`search_semantic_scholar`**: "What are the most cited papers on attention mechanisms?" — should return papers sorted by relevance, with citation counts
3. **`download_paper`**: "Download that first paper and add it to my library" — agent should confirm, then download and import
4. **`add_to_collection`**: "Add it to my 'RAG Papers' collection" — should create collection if needed, add the document
5. **Full chain**: "Find papers about X, download the most relevant one, and add it to my Y collection" — agent chains search → confirm → download → add_to_collection
6. **Error cases**:
   - Search with no results → graceful message
   - Download a paywalled paper (no PDF URL) → agent explains it's not freely available
   - Download from disallowed domain → error
   - Download timeout → error with retry suggestion
7. **Regression**: Existing tools (search_document, create_highlight, etc.) still work unchanged
