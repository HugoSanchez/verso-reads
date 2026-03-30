# Agentic Architecture Research for Verso Reads

> Deep research into how to add agentic AI capabilities to Verso Reads — a native macOS reading app built in SwiftUI.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [How Production Agents Work Today](#2-how-production-agents-work-today)
3. [The Agentic Loop Pattern](#3-the-agentic-loop-pattern)
4. [API Options: OpenAI vs Anthropic](#4-api-options-openai-vs-anthropic)
5. [Tool Design for Verso Reads](#5-tool-design-for-verso-reads)
6. [Architecture Recommendation](#6-architecture-recommendation)
7. [Implementation Plan (Original)](#7-implementation-plan)
8. [External APIs for Future Capabilities](#8-external-apis-for-future-capabilities)
9. [Context Management Strategies](#9-context-management-strategies)
10. [Critical Challenges & Hard Problems](#10-critical-challenges--hard-problems)
11. [On-Device Models: A Strategic Advantage](#11-on-device-models-a-strategic-advantage)
12. [Other Production Agents Worth Studying](#12-other-production-agents-worth-studying)
13. [Revised Implementation Plan](#13-revised-implementation-plan)

---

## 1. Executive Summary

After deep research into how Claude Code, Cursor, OpenAI Codex, and the OpenAI/Anthropic APIs work, the core insight is surprisingly simple:

**Every production agent is just a `while` loop.**

The model gets a prompt with available tools, decides whether to call one, you execute it locally, feed the result back, and loop until the model says "I'm done." That's it. Claude Code, Cursor, Codex — they all use this same pattern. The sophistication is in the *tools you expose* and the *system prompt* that teaches the model when to use them, not in the loop itself.

For Verso Reads, this means:
- **We don't need a framework.** We can build the agent loop directly in Swift, extending the existing `OpenAIClient`.
- **The hard part is tool design**, not infrastructure. Choosing the right set of tools for a reading assistant is the key architectural decision.
- **We're already 70% there.** The existing RAG pipeline, annotations system, and chat UI are the foundation. We need to wire them up as callable tools and add the agentic loop.

---

## 2. How Production Agents Work Today

### 2.1 Claude Code

Claude Code is the best-documented production agent. Its architecture is instructive:

**Core loop**: A single-threaded master loop (`while tool_call → execute → feed result → repeat`). Three phases blend together: *gather context*, *take action*, *verify results*.

**Tools** (5 categories):
| Category | What it does |
|---|---|
| File operations | Read files, edit code, create files |
| Search | Find files by pattern, search content with regex |
| Execution | Run shell commands, tests, git |
| Web | Search the web, fetch documentation |
| Code intelligence | Type errors, jump to definitions |

**Key design decisions:**
- **Single-threaded by design.** One flat message history. No competing agent personas. This avoids the unpredictable behaviors that multi-agent systems introduce.
- **Sub-agents for parallelism.** When exploration is needed, Claude Code spawns sub-agents with their own context windows, depth-limited to prevent recursive sprawl. Sub-agents return summaries, keeping the main context clean.
- **Planning via TodoWrite.** Structured JSON task lists with IDs, status tracking, and priority levels. These render as interactive checklists. Reminder injection after tool uses keeps the model on track.
- **Context management.** Auto-compaction when approaching limits. CLAUDE.md files for persistent instructions. Auto-memory for cross-session learning.

**Source:** [How Claude Code Works](https://code.claude.com/docs/en/how-claude-code-works), [Claude Code Behind the Scenes](https://blog.promptlayer.com/claude-code-behind-the-scenes-of-the-master-agent-loop/)

### 2.2 Cursor

Cursor 2.0 shipped its "Composer" agent in October 2025, moving from code suggestions to autonomous coding.

**Architecture:**
- **Router + Model Selection**: An "Auto" mode routes requests to appropriate models based on complexity.
- **Control loop (ReAct pattern)**: The orchestrator runs the loop — model decides what to do → orchestrator executes the tool call → collects result → rebuilds context → sends back to model.
- **10+ tools**: Codebase search, file read/write, edit application, terminal commands.
- **Sandbox execution**: Tool calls run in isolated environments with strict guardrails.
- **Context compaction**: Retains stable signals (failing test names, error types, key stack frames), deduplicates repeated snippets, keeps raw artifacts external to the prompt.

**Key insight from Cursor:** They trained their Composer model specifically on *trajectories* — sequences of tool actions that solve problems — not just next-token prediction. This is why it knows when to search vs. edit vs. run tests. For Verso Reads, we get this behavior through good system prompts and tool descriptions rather than model training.

**Source:** [How Cursor Shipped its Coding Agent](https://blog.bytebytego.com/p/how-cursor-shipped-its-coding-agent)

### 2.3 OpenAI Codex / Agents SDK

OpenAI's approach has evolved significantly:

- **Responses API** (replaces Chat Completions): "Agentic by default" — the model can call multiple tools within a single API request. Built-in tools include `web_search`, `file_search`, `code_interpreter`, and remote MCP servers.
- **OpenAI Agents SDK**: Lightweight Python framework with three primitives: Agents (LLMs with tools), Handoffs (agent-to-agent delegation), and Guardrails (input/output validation).
- **Strict mode**: Setting `strict: true` on tool definitions ensures tool calls reliably match the schema via structured outputs. OpenAI recommends always enabling this.

**Source:** [OpenAI Agents SDK](https://openai.github.io/openai-agents-python/), [Building Agents](https://developers.openai.com/tracks/building-agents)

---

## 3. The Agentic Loop Pattern

### 3.1 The ReAct Pattern

All production agents implement a variant of the **ReAct** (Reason + Act) pattern from Yao et al. (2022):

```
User message
    ↓
┌─────────────────────────┐
│  Model receives:        │
│  - System prompt        │
│  - Tool definitions     │
│  - Conversation history │
│  - User message         │
│                         │
│  Model outputs:         │
│  - Text (reasoning)     │
│  - OR tool call(s)      │
└─────────┬───────────────┘
          │
    ┌─────▼─────┐
    │ Tool call? │──No──→ Return text to user
    └─────┬─────┘
          │ Yes
    ┌─────▼─────────────┐
    │ Execute tool(s)   │
    │ locally            │
    └─────┬─────────────┘
          │
    ┌─────▼─────────────┐
    │ Feed result back  │
    │ to model          │
    └─────┬─────────────┘
          │
          └──→ Loop back to model
```

### 3.2 How It Works with the OpenAI Responses API

Since Verso Reads already uses the Responses API (`/v1/responses`), here's the exact flow:

**Step 1 — Send request with tools:**
```json
{
  "model": "gpt-5.2",
  "input": [
    {"role": "system", "content": "You are a reading assistant with tools..."},
    {"role": "user", "content": "Highlight everywhere this document discusses epistemology"}
  ],
  "tools": [
    {
      "type": "function",
      "name": "search_document",
      "description": "Search the current document for passages matching a query",
      "parameters": {
        "type": "object",
        "properties": {
          "query": {"type": "string", "description": "The search query"},
          "max_results": {"type": "integer", "description": "Max chunks to return"}
        },
        "required": ["query"],
        "additionalProperties": false
      },
      "strict": true
    },
    {
      "type": "function",
      "name": "create_highlight",
      "description": "Highlight a specific passage in the document",
      "parameters": {
        "type": "object",
        "properties": {
          "quote": {"type": "string", "description": "Exact text to highlight"},
          "page": {"type": "integer", "description": "Page number"},
          "color": {"type": "string", "enum": ["yellow", "orange", "green", "blue"]}
        },
        "required": ["quote", "page", "color"],
        "additionalProperties": false
      },
      "strict": true
    }
  ],
  "stream": true
}
```

**Step 2 — Model responds with tool call:**

When streaming, tool calls arrive as SSE events of type `response.function_call_arguments.delta` and `response.function_call_arguments.done`. The key events are:

```
event: response.output_item.added       → new output item (tool call)
event: response.function_call_arguments.delta  → partial JSON args
event: response.function_call_arguments.done   → complete JSON args
```

Once you have the complete function call, you get something like:
```json
{
  "type": "function_call",
  "id": "fc_123",
  "call_id": "call_abc",
  "name": "search_document",
  "arguments": "{\"query\": \"epistemology\", \"max_results\": 10}"
}
```

**Step 3 — Execute locally and send result back:**
```json
{
  "model": "gpt-5.2",
  "input": [
    ...previous messages...,
    {
      "type": "function_call_output",
      "call_id": "call_abc",
      "output": "[{\"text\": \"The epistemological foundations...\", \"page\": 12}, ...]"
    }
  ],
  "tools": [...same tools...],
  "stream": true
}
```

**Step 4 — Loop until the model stops calling tools.**

### 3.3 Parallel Tool Calls

Both OpenAI and Anthropic support the model calling multiple tools in a single turn. For example, the model might call `search_document` three times with different queries simultaneously. You execute all of them and send all results back in one request.

### 3.4 The Anthropic/Claude API Equivalent

For reference (if we ever want to support Claude models), the Anthropic API uses:
- `tool_use` content blocks (model → your app)
- `tool_result` content blocks (your app → model)
- `stop_reason: "tool_use"` signals the model wants to call a tool
- Loop while `stop_reason == "tool_use"`

The pattern is identical; only the JSON shape differs.

---

## 4. API Options: OpenAI vs Anthropic

### 4.1 Current State: OpenAI Responses API

Verso Reads currently uses the OpenAI Responses API with `gpt-5.2`. This is a solid foundation:

**Pros:**
- Already integrated (SSE streaming works)
- Responses API is "agentic by default" — built-in support for tool calling
- Strict mode ensures tool calls match schemas exactly
- Built-in tools available (`web_search` for future use)
- Lower costs via improved cache utilization (40-80% improvement over Chat Completions)
- Stateful context via `store: true` (maintain state turn-to-turn without resending everything)

**Cons:**
- Direct HTTP implementation (no Swift SDK with tool-call abstractions)
- Need to extend SSE parser to handle tool call events (currently only handles `response.output_text.delta`)

### 4.2 Alternative: Anthropic Claude API

**Pros:**
- Claude models are excellent at tool use (specifically trained for it)
- Anthropic-schema tools (`bash`, `text_editor`) are battle-tested
- MCP (Model Context Protocol) is becoming an industry standard
- Extended thinking with tool use for complex reasoning
- Server-side tools (`web_search`, `code_execution`) run on Anthropic infra
- Tool Search Tool: dynamic tool discovery, 85% reduction in token usage

**Cons:**
- Would require a new API client
- Different JSON format for tool definitions
- No Swift SDK (would need to build from scratch like OpenAI client)

### 4.3 Recommendation

**Start with OpenAI** — we're already using it and the Responses API has everything we need. The tool-calling extension to `OpenAIClient.swift` is straightforward.

**Design tool definitions as provider-agnostic** — define tools as Swift structs with name, description, and parameter schema. Serialize to OpenAI format now; add Anthropic serialization later if needed. This costs almost nothing extra and gives us optionality.

### 4.4 Swift Libraries Worth Considering

- **[MacPaw/OpenAI](https://github.com/MacPaw/OpenAI)**: Community Swift package for OpenAI API, supports function calling
- **[SwiftOpenAI](https://github.com/jamesrochabrun/SwiftOpenAI)**: Most complete Swift package for OpenAI, supports iOS 15+/macOS 13+

However, given that our custom `OpenAIClient` is already working well with the Responses API and SSE streaming, **extending it directly is simpler** than adopting a third-party library. We just need to add tool call parsing to the SSE handler.

---

## 5. Tool Design for Verso Reads

This is the most important section. The tools we expose define what the agent can do.

### 5.1 Proposed Tool Set

#### Tier 1: Core Tools (Build First)

| Tool | Description | Maps To |
|---|---|---|
| `search_document` | RAG search the current document for relevant passages | `RAGQueryService.retrieveContext()` |
| `get_document_info` | Get metadata about the current document (title, page count, etc.) | `LibraryDocument` properties |
| `get_page_text` | Read the full text of a specific page | `RAGTextExtractor` |
| `create_highlight` | Highlight a passage on a specific page with a color | Create `Annotation` with kind `.highlight` |
| `delete_highlight` | Remove a highlight by ID | Delete `Annotation` |
| `create_note` | Add a note to the document's notepad | Update `DocumentNote.content` |
| `get_notes` | Read the current notes for this document | Read `DocumentNote.content` |
| `get_highlights` | List all highlights in the current document | Query `Annotation` by documentID |

#### Tier 2: Enhanced Tools (Build Second)

| Tool | Description | Maps To |
|---|---|---|
| `search_all_documents` | Search across ALL user documents, not just the current one | `RAGStore.searchSimilar()` across all docs |
| `get_library` | List all documents in the user's library | Query all `LibraryDocument` |
| `get_collections` | List document collections | Query `DocumentCollection` |
| `get_chat_history` | Read past chat conversations about a document | Query `ChatMessageRecord` |
| `create_highlight_with_note` | Highlight + attach a note to it | Create `Annotation` with `.comment` kind |

#### Tier 3: External Tools (Future)

| Tool | Description | Implementation |
|---|---|---|
| `search_arxiv` | Search arXiv for related academic papers | arXiv REST API |
| `search_semantic_scholar` | Search Semantic Scholar for papers | Semantic Scholar API |
| `web_search` | General web search | OpenAI built-in `web_search` tool or custom |

### 5.2 Tool Definition Examples (Swift)

```swift
struct AgentTool {
    let name: String
    let description: String
    let parameters: [String: Any]  // JSON Schema

    func toOpenAIFormat() -> [String: Any] {
        return [
            "type": "function",
            "name": name,
            "description": description,
            "parameters": parameters,
            "strict": true
        ]
    }
}

// Example: search_document
let searchDocumentTool = AgentTool(
    name: "search_document",
    description: """
    Search the current document for passages relevant to a query.
    Returns the most similar text chunks with page numbers.
    Use this when you need to find specific information in the document
    to answer a question, find passages to highlight, or verify claims.
    """,
    parameters: [
        "type": "object",
        "properties": [
            "query": [
                "type": "string",
                "description": "The semantic search query"
            ],
            "max_results": [
                "type": "integer",
                "description": "Maximum number of chunks to return (default 4)"
            ]
        ],
        "required": ["query"],
        "additionalProperties": false
    ]
)
```

### 5.3 System Prompt Design

The system prompt is critical — it teaches the model *when* to use tools vs. answer directly. Here's a draft:

```
You are a reading assistant embedded in a document reader app. You help users
deeply engage with their reading — understanding texts, finding connections,
taking notes, and organizing highlights.

## When to use tools

- **search_document**: Use when the user asks about the content of the document,
  wants to find specific passages, or when you need to verify information before
  answering. Do NOT search for simple factual questions you can answer from
  general knowledge.

- **create_highlight / delete_highlight**: Use when the user explicitly asks to
  highlight or un-highlight text. When highlighting a topic, first search for
  relevant passages, then highlight each one.

- **create_note / get_notes**: Use when the user asks to take a note, summarize
  something into notes, or when you want to check existing notes for context.

- **get_highlights**: Use when the user asks about their highlights, wants a
  summary of what they've marked, or when you need context about what they've
  found important.

## When NOT to use tools

- General knowledge questions that don't require document content
- Follow-up questions where you already have the relevant context from a
  previous tool call in this conversation
- Simple conversational responses

## Behavior

- Be concise but thorough
- Reference specific pages when discussing document content
- When asked to highlight a topic, search first, then highlight each relevant passage
- When asked a question, decide whether you need document context or can answer directly
- Proactively suggest connections between ideas in the document and the user's notes
```

### 5.4 Key Design Decision: Autonomous RAG

Currently, RAG happens on every user message (if no text is selected). With the agentic approach, **the model decides when to search**. This is fundamentally better because:

1. **Not every question needs RAG.** "What does epistemology mean?" doesn't need a document search. The current approach wastes an embedding API call + vector search on this.
2. **Some questions need multiple searches.** "Compare the author's view on X with their view on Y" might need two separate searches with different queries.
3. **The model can search iteratively.** If the first search doesn't find what it needs, it can refine the query and search again.
4. **Cross-document search becomes possible.** The model can decide to search other documents in the library when the current document doesn't have the answer.

---

## 6. Architecture Recommendation

### 6.1 High-Level Architecture

```
┌─────────────────────────────────────────────┐
│                  ChatView                    │
│  (UI: messages, input, streaming display)    │
└──────────────────┬──────────────────────────┘
                   │
         ┌─────────▼─────────┐
         │   AgentRunner     │
         │  (the while loop) │
         └─────────┬─────────┘
                   │
    ┌──────────────▼──────────────┐
    │      OpenAIClient           │
    │  (extended for tool calls)  │
    └──────────────┬──────────────┘
                   │
         ┌─────────▼─────────┐
         │   ToolExecutor    │
         │  (dispatches to   │
         │   tool handlers)  │
         └─────────┬─────────┘
                   │
    ┌──────┬───────┼───────┬──────┐
    ▼      ▼       ▼       ▼      ▼
  RAG   Annotations  Notes  Library  (future: arXiv)
```

### 6.2 New Components Needed

#### `AgentRunner` (new service)
The core agentic loop. Owns the `while` loop. Receives a user message, runs the model, executes tool calls, feeds results back, repeats until done. Yields streaming text deltas for the UI to display.

```swift
class AgentRunner: ObservableObject {
    let client: OpenAIClient
    let toolExecutor: ToolExecutor
    let tools: [AgentTool]

    func run(
        systemPrompt: String,
        messages: [OpenAIClient.Message],
        tools: [AgentTool]
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        // AgentEvent = .textDelta(String) | .toolCall(name, args) | .toolResult(name, result) | .done
    }
}
```

#### `ToolExecutor` (new service)
Dispatches tool calls to the appropriate handler. Each tool maps to an existing service:

```swift
class ToolExecutor {
    let ragService: RAGQueryService
    let modelContext: ModelContext
    // ...

    func execute(toolName: String, arguments: [String: Any]) async throws -> String {
        switch toolName {
        case "search_document": return try await executeSearchDocument(arguments)
        case "create_highlight": return try await executeCreateHighlight(arguments)
        case "create_note": return try await executeCreateNote(arguments)
        // ...
        }
    }
}
```

#### Extensions to `OpenAIClient` (modify existing)
Add tool call parsing to the SSE handler. Currently it only handles `response.output_text.delta`. Need to also handle:
- `response.output_item.added` (new output item — could be text or tool call)
- `response.function_call_arguments.delta` (partial tool call arguments)
- `response.function_call_arguments.done` (complete tool call)
- `response.completed` (the model is done — check if there are tool calls to execute)

The response will contain both text and tool calls interleaved. The streaming flow becomes:

```swift
enum StreamEvent {
    case textDelta(String)
    case functionCallStart(id: String, callId: String, name: String)
    case functionCallArgumentsDelta(callId: String, delta: String)
    case functionCallArgumentsDone(callId: String, arguments: String)
    case completed(output: [OutputItem])  // may contain function_call items
}
```

### 6.3 Changes to ChatView

The ChatView needs minimal changes:
1. Replace direct `OpenAIClient.streamResponse()` calls with `AgentRunner.run()`
2. Handle `AgentEvent.toolCall` and `AgentEvent.toolResult` for UI feedback (optional: show "Searching document...", "Creating highlight...", etc.)
3. The streaming text display stays the same — the UI just receives text deltas as before

### 6.4 What We Keep

- **All existing models** (Annotation, LibraryDocument, ChatMessage, etc.)
- **All existing RAG infrastructure** (RAGStore, RAGChunker, RAGIngestionManager, RAGQueryService)
- **The chat UI** (ChatView, message bubbles, markdown rendering)
- **The OpenAI client** (just extend it)

---

## 7. Implementation Plan

### Phase 1: Foundation (The Loop)
1. Extend `OpenAIClient` to parse tool call SSE events
2. Create `AgentTool` struct for defining tools
3. Create `AgentRunner` with the agentic while loop
4. Create `ToolExecutor` with `search_document` as the first tool
5. Wire `AgentRunner` into `ChatView` as the default path (replacing the current direct streaming)

**Result:** The agent can decide whether to search the document or answer directly. This alone is a significant UX improvement over the current "always RAG" approach.

### Phase 2: Reading Tools
6. Add `create_highlight` tool (requires mapping text quotes to PDF positions)
7. Add `delete_highlight` tool
8. Add `get_highlights` tool
9. Add `create_note` / `get_notes` tools
10. Add `get_page_text` tool for full-page reading

**Result:** The agent can read, highlight, and take notes.

### Phase 3: Cross-Document Intelligence
11. Add `search_all_documents` tool
12. Add `get_library` / `get_collections` tools
13. Add `get_chat_history` tool

**Result:** The agent has full context of the user's reading history and can connect ideas across documents.

### Phase 4: External Research
14. Add `search_arxiv` tool (arXiv API)
15. Add `search_semantic_scholar` tool (Semantic Scholar API)
16. Consider OpenAI built-in `web_search` tool

**Result:** The agent can find related academic work and external resources.

### Phase 5: UI Polish
17. Show tool execution status in chat (e.g., "Searching document...", "Adding highlight...")
18. Show tool results inline (e.g., search results as collapsible cards)
19. Add ability for user to approve/reject tool actions before execution (optional)

---

## 8. External APIs for Future Capabilities

### 8.1 arXiv API

**Endpoint:** `http://export.arxiv.org/api/query`
**Format:** Atom 1.0 XML
**Rate limit:** Max 1 request every 3 seconds
**Authentication:** None required

Example search:
```
GET http://export.arxiv.org/api/query?search_query=all:transformer+attention&max_results=5
```

Returns titles, authors, abstracts, PDF links, categories, and dates.

**Source:** [arXiv API Documentation](https://info.arxiv.org/help/api/index.html)

### 8.2 Semantic Scholar API

**Endpoint:** `https://api.semanticscholar.org/graph/v1/paper/search`
**Format:** JSON
**Rate limit:** 1000 req/sec (unauthenticated, shared)
**Authentication:** Optional API key for higher limits

Features:
- Paper search with ranking
- Citation graph traversal
- Author information
- SPECTER2 embeddings for semantic similarity
- Bulk search with advanced filtering

**Source:** [Semantic Scholar API](https://www.semanticscholar.org/product/api)

### 8.3 OpenAlex API (Citation Graphs)

**Endpoint:** `https://api.openalex.org/works?search=...`
**Format:** JSON
**Rate limit:** Generous, no auth required
**Authentication:** None

Free, open alternative to Microsoft Academic Graph. Excellent for citation graph exploration — "what papers cite this one?" and "what papers does this one cite?" Good complement to arXiv (preprints) and Semantic Scholar (ranking + TLDRs).

### 8.4 CrossRef API (DOI Resolution)

**Endpoint:** `https://api.crossref.org/works?query=...`
**Format:** JSON
**Authentication:** None (add `mailto` parameter for polite pool)

Good for DOI resolution and metadata lookup. Useful when the user has a DOI and wants full paper metadata.

### 8.5 OpenAI Built-in Web Search

The Responses API supports a built-in `web_search` tool that runs on OpenAI's infrastructure. You just add it to the tools array:

```json
{
  "type": "web_search_preview",
  "search_context_size": "medium"
}
```

No execution needed on our side — OpenAI handles it. The model searches the web, reads results, and incorporates them into its response automatically.

### 8.4 MCP (Model Context Protocol)

MCP is becoming an industry standard for tool definitions. Anthropic introduced it in late 2024, donated it to the Linux Foundation in December 2025, and Apple added native MCP support in Xcode 26.3. OpenAI added MCP support in ChatGPT.

**Relevance for Verso Reads:** MCP could be a future extensibility mechanism — allowing users to connect their own tools (e.g., a Notion MCP server to sync notes, a Zotero MCP server for bibliography management). Not needed now, but worth keeping in mind for the architecture.

There's also a Semantic Scholar MCP server already available, which could be integrated directly.

---

## 9. Context Management Strategies

### 9.1 The Problem

Tool results add tokens to the conversation. If the agent calls `search_document` 5 times, that's potentially 5 × 1200 characters of chunk text added to the context. Over a long conversation, this bloats quickly.

### 9.2 How Production Agents Handle This

**Claude Code:**
- Auto-compaction when approaching context limits
- Clears older tool outputs first, then summarizes conversation
- CLAUDE.md for persistent instructions that survive compaction
- Sub-agents with fresh contexts for exploration tasks

**Cursor:**
- Context compaction: retains stable signals (error types, key findings), deduplicates repeated snippets
- Keeps raw artifacts external to the prompt
- Custom embedding model for codebase recall

### 9.3 Hierarchical Memory Model

The best approach for a reading agent is hierarchical:

| Layer | What | Where | Lifetime |
|---|---|---|---|
| **Working memory** | Current conversation + recent tool results | API context window | This turn |
| **Short-term memory** | Summarized older tool results | Compressed in context | This session |
| **Long-term memory** | User's highlights, notes, documents | On-disk (SwiftData + sqlite-vec) | Persistent |

The agent doesn't hold everything in context — it searches long-term memory via tools (`search_document`, `get_highlights`, `get_notes`) and only pulls in what it needs.

### 9.4 Strategies for Verso Reads

1. **Conversation history limit** (already exists): Keep last N messages. Currently `historyLimit = 12`. May need to increase for agentic conversations where tool calls count as messages.

2. **Tool result summarization**: After a tool result is consumed (model has seen it and produced a response), replace the full result with a summary in subsequent turns. E.g., `search_document` returned 4 chunks → summarize as "Found 4 relevant passages on pages 12, 15, 23, 31."

3. **Tool result truncation**: Limit what tools return. `search_document` returns top 4 results with truncated text. If the agent needs more detail, it can call `get_page_text` to drill into a specific page. This "search then drill down" pattern keeps token usage manageable.

4. **Stateful API** (OpenAI Responses API feature): Use `store: true` and `previous_response_id` to let OpenAI maintain state server-side. This avoids resending the full conversation on every turn and improves cache hit rates.

5. **Fresh context for complex tasks**: For multi-step operations like "highlight every mention of epistemology," consider running the operation in a focused context with just the task description and results, not the full conversation history.

6. **Research session model**: The agent accumulates findings in the user's notes as it works. Even if conversation history gets truncated, the synthesized knowledge persists in the notepad. This is a natural fit — the agent's output becomes the user's artifact.

---

## 10. Critical Challenges & Hard Problems

### 10.1 HARD PROBLEM: Text-to-PDF-Coordinates for Highlights

**Severity: High — this is the hardest technical problem in the project.**

The `create_highlight` tool needs to map a text quote (from the model) to PDF visual coordinates. The current `Annotation` model stores `anchorData: Data`, which is a serialized `PDFHighlightAnchor` containing normalized page coordinates (`fragments[].rects[].x/y/w/h`).

**The challenge:**
1. `PDFDocument.findString()` does exact matching — if the model's quote has a single extra space, missing hyphen, or different Unicode normalization, the search fails silently.
2. PDF text extraction often produces artifacts (ligatures, special characters, line-break hyphenation) that don't match the model's quote.
3. We need to go from `PDFSelection` bounds → normalized coordinates → `PDFHighlightAnchor` data.

**Recommended approach:**
1. Use `PDFPage.selection(for:)` with the quote text
2. If exact match fails, try fuzzy matching: strip whitespace/punctuation, try substrings
3. Normalize selection bounds relative to the page's media box
4. Serialize into the existing `PDFHighlightAnchor` format
5. **Write a dedicated `PDFTextMatcher` service** with thorough test coverage before attempting the tool

**This needs a dedicated technical spike before implementation.** Estimate at least a full sprint to get reliable text-to-highlight mapping.

### 10.2 HARD PROBLEM: Notes are Tiptap JSON, Not Plain Text

The `DocumentNote.content` field stores Tiptap editor JSON (rich text), not plain text or markdown. The agent will produce plain text or markdown. There's an impedance mismatch.

**Options:**
1. **Markdown → Tiptap JSON converter**: Build a Swift function that converts markdown to Tiptap's JSON document format (paragraph nodes, heading nodes, bold/italic marks, etc.)
2. **Append-only via simple nodes**: The agent appends new content as plain paragraph nodes to the existing Tiptap JSON tree, without touching the user's formatted notes.
3. **Separate agent notes section**: Keep a dedicated plain-text section in the notepad for agent-generated notes, separate from the user's rich-text notes.

Option 2 is the pragmatic choice for v1.

### 10.3 Error Recovery and Cancellation

**Error recovery:** Every tool call can fail. The `AgentRunner` needs:
- A `ToolResult` type that represents success or failure
- Logic to feed errors back to the model: "Tool `search_document` failed: database unavailable"
- Retry logic with backoff for transient failures (network errors)
- Graceful degradation: if RAG is broken, the agent should still answer from general knowledge

**Cancellation:** The user must be able to abort a running agent loop. This requires:
- Cooperative cancellation via `Task.isCancelled` checks at each iteration
- A cancel button in the ChatView during agentic execution
- Clean state on cancellation (don't leave partial highlights)

**Undo/Batch undo:** If the agent creates 15 highlights in one turn and the user didn't want that, they need to undo all of them at once. The agent should tag all actions from a single turn with a `turnID`, enabling "undo all actions from this turn."

### 10.4 SwiftData Concurrency

**This is a hard constraint the architecture must address.**

`ModelContext` is not thread-safe. The `AgentRunner` loop runs in a background `Task`. Tools like `create_highlight` and `create_note` need to write to SwiftData. This will crash if accessed from the wrong actor.

**Solution:** The `ToolExecutor` must funnel all SwiftData operations through `@MainActor`:
```swift
@MainActor
func executeCreateHighlight(_ args: [String: Any]) async throws -> ToolResult {
    // Safe to access modelContext here
}
```

Or create a dedicated background `ModelContext` for the tool executor (SwiftData supports this but requires careful setup).

### 10.5 Tool Argument Validation

The model WILL sometimes hallucinate tool arguments. Even with `strict: true` (which only guarantees JSON schema conformance, not semantic correctness):
- `create_highlight` with a quote that doesn't exist in the document
- `create_highlight` with the wrong page number
- `delete_highlight` with a nonexistent annotation ID

**Every write tool needs validation:**
- Verify the quote exists on the specified page before creating a highlight
- Verify the annotation ID exists before deleting
- Return clear error messages so the model can self-correct

### 10.6 Token Cost

Agentic loops use more tokens than single-turn chat. A single question might trigger 3-5 API round trips.

**Mitigations:**
- Use `store: true` + `previous_response_id` for server-side state (avoid resending full conversation)
- Hard limit on max tool calls per turn (e.g., 15 iterations)
- Consider a cheaper/faster model for simple queries that don't need tools
- On-device intent classification to skip tools entirely for simple questions (see Section 11)

### 10.7 Latency

Each tool call = at least one extra API round trip (1-3 seconds).

**Mitigations:**
- Show streaming text immediately when the model starts responding
- Show tool execution status in the chat UI ("Searching document..." with spinner) — **this is Phase 1 work, not polish**
- Parallel tool execution when the model calls multiple tools at once
- Local tools (sqlite-vec search) are fast; external APIs (arXiv) will be slower

### 10.8 `strict: true` Schema Requirements

When `strict: true` is set, ALL parameters must be `required` (no optional fields), and `additionalProperties: false` must be set at every nested object level. The example `search_document` tool has `max_results` as optional — this will fail.

**Fix:** Make all parameters required with sensible defaults described in the description, or use nullable types (`"type": ["integer", "null"]`).

### 10.9 Missing Tools (Identified in Review)

| Tool | Why It's Needed |
|---|---|
| `navigate_to_page` | Agent finds something on page 47 → user should see it |
| `get_table_of_contents` | Structural navigation without searching every page |
| `get_current_page` | Context about what the user is reading right now |
| `update_highlight` | Change highlight color (already supported in UI) |

### 10.10 Model Provider Flexibility

Building the tool execution layer as provider-agnostic (define tools in Swift, serialize to API format) gives us the option to support Claude models later. The Anthropic API has slightly different JSON formats but the same conceptual model (tool_use → execute → tool_result → loop).

---

## 11. On-Device Models: A Strategic Advantage

This is the biggest strategic opportunity for a native macOS app.

### 11.1 Why On-Device Matters for a Reading App

1. **Privacy.** Users read potentially sensitive documents (legal, medical, personal research). Some will not want their document text sent to cloud APIs. On-device models are a differentiator.
2. **Cost.** The agentic loop multiplies API calls. If the agent searches 5 times per question, that's 5 embedding API calls + multiple chat completions. On-device models for routing and embeddings cut this significantly.
3. **Latency.** On-device inference eliminates network round trips. For the "should I use a tool?" decision, this could save 1-2 seconds per message.
4. **Offline support.** Users can read and interact with the agent on a plane.

### 11.2 Apple Foundation Models (macOS 26+)

Apple ships on-device foundation models with tool-calling support starting in macOS 26. These models are available through the `FoundationModels` framework.

**Potential uses in Verso Reads:**
- **Intent classification / tool routing**: "Does this message need tools?" A small on-device model can make this decision without an API call, saving cost on 30-50% of messages.
- **Simple Q&A**: General knowledge questions ("What does epistemology mean?") answered locally.
- **Summarization**: Summarize a page or chapter without sending text to the cloud.

**Limitations:** Lower quality than GPT-5.2 or Claude. Not suitable for complex multi-step reasoning or nuanced tool dispatch decisions. Best used as a fast-path for simple cases, with cloud models as the fallback.

### 11.3 On-Device Embeddings

Apple's `NaturalLanguage` framework includes sentence embeddings. They're lower quality than `text-embedding-3-small` (1536 dims) but:
- Free (no API cost)
- Instant (no network latency)
- Private (text stays on device)

**Potential use:** For the `search_document` tool in the agentic loop, where the agent might search 5 times per turn, on-device embeddings would cut latency and cost dramatically. Could use a hybrid approach: on-device embeddings for real-time search during agent loops, cloud embeddings for initial document indexing (higher quality).

### 11.4 Hybrid Architecture (Recommended Long-Term)

```
User message
    ↓
┌─────────────────────────┐
│ On-device classifier    │
│ "Needs tools?" / simple │
└─────────┬───────────────┘
          │
    ┌─────▼─────┐
    │  Simple?  │──Yes──→ On-device model answers directly
    └─────┬─────┘
          │ No (needs tools / complex reasoning)
    ┌─────▼─────────────┐
    │  Cloud model       │
    │  (GPT-5.2/Claude)  │
    │  with tool calling │
    └────────────────────┘
```

This is a Phase 5+ goal, not something to build now. But the architecture should not preclude it — design the `AgentRunner` with a model abstraction that can swap between providers.

---

## 12. Other Production Agents Worth Studying

### 12.1 Perplexity

**Most relevant analogue to Verso Reads.** Perplexity is a research/reading agent that:
- Decides when to search vs. answer from knowledge
- Synthesizes results from multiple sources
- Cites sources with inline references
- Iterates on searches when initial results are insufficient

**Key takeaway:** Their source attribution and citation formatting (inline page/source references) is directly relevant to how our agent should reference page numbers.

### 12.2 Replit Agent / Devin

Pushed the boundary on long-running agentic tasks with user checkpoints. Relevant for the "highlight everything about X in this 200-page document" use case where the agent works for 30+ seconds.

**Key takeaway:** Checkpoint systems that let users review progress mid-execution and abort if the agent is going in the wrong direction.

### 12.3 LangGraph / CrewAI

We don't need these frameworks, but they've solved problems we'll encounter:
- State persistence across agent turns
- Human-in-the-loop approval flows
- Parallel tool execution patterns
- Structured agent state machines

Worth reading their docs for patterns, not for adoption.

---

## 13. Revised Implementation Plan

Based on the critical review, here's the updated phasing:

### Phase 1: Foundation + Basic Tools + Status UI
1. Extend `OpenAIClient` SSE parser for tool call events
2. Create `AgentTool` definition struct (provider-agnostic)
3. Create `AgentRunner` with the agentic while loop, cancellation, error handling
4. Create `ToolExecutor` with initial tools:
   - `search_document` (RAG search)
   - `get_highlights` (read-only, trivial)
   - `get_notes` (read-only, trivial)
   - `get_document_info` (read-only, trivial)
   - `get_current_page` (read-only)
   - `get_table_of_contents` (read-only)
5. Wire `AgentRunner` into `ChatView`
6. **Show tool execution status in chat** (spinner + tool name during execution)
7. Add cancel button for running agent loops

**Result:** Agent autonomously decides when to search. Read-only tools give it full context. Tool status visible in UI.

### Phase 2: Write Tools
8. Build `PDFTextMatcher` service (dedicated spike for text → PDF coordinates)
9. Add `create_highlight` tool with argument validation
10. Add `delete_highlight` tool
11. Add `update_highlight` tool (change color)
12. Add `navigate_to_page` tool
13. Add `create_note` tool (append paragraph nodes to Tiptap JSON)
14. Add `get_page_text` tool
15. Implement batch undo (tag actions by turn ID)

**Result:** Agent can read, highlight, navigate, and take notes.

### Phase 3: Cross-Document Intelligence
16. Add `search_all_documents` tool
17. Add `get_library` / `get_collections` tools
18. Add `get_chat_history` tool

**Result:** Agent has full context across user's library.

### Phase 4: External Research
19. Add `search_arxiv` tool
20. Add `search_semantic_scholar` tool
21. Consider OpenAI built-in `web_search` tool

### Phase 5: Optimization
22. Implement `store: true` + `previous_response_id` for stateful API calls
23. Tool result summarization (compress old tool results in conversation)
24. Evaluate on-device models for intent classification
25. Evaluate on-device embeddings for agent search loops

---

## Appendix A: Key Resources

- [OpenAI Function Calling Guide](https://platform.openai.com/docs/guides/function-calling)
- [OpenAI Responses API Migration Guide](https://developers.openai.com/api/docs/guides/migrate-to-responses)
- [OpenAI Responses Streaming Events](https://platform.openai.com/docs/api-reference/responses-streaming)
- [OpenAI Agents SDK](https://openai.github.io/openai-agents-python/)
- [OpenAI Building Agents Track](https://developers.openai.com/tracks/building-agents)
- [How Claude Code Works](https://code.claude.com/docs/en/how-claude-code-works)
- [Claude Code Agent Architecture (ZenML)](https://www.zenml.io/llmops-database/claude-code-agent-architecture-single-threaded-master-loop-for-autonomous-coding)
- [Tracing Claude Code's LLM Traffic](https://medium.com/@georgesung/tracing-claude-codes-llm-traffic-agentic-loop-sub-agents-tool-use-prompts-7796941806f5)
- [How Cursor Shipped its Coding Agent](https://blog.bytebytego.com/p/how-cursor-shipped-its-coding-agent)
- [Anthropic Tool Use Documentation](https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview)
- [Anthropic Advanced Tool Use](https://www.anthropic.com/engineering/advanced-tool-use)
- [ReAct Pattern](https://www.promptingguide.ai/techniques/react)
- [arXiv API Documentation](https://info.arxiv.org/help/api/index.html)
- [Semantic Scholar API](https://www.semanticscholar.org/product/api)
- [MacPaw/OpenAI Swift Package](https://github.com/MacPaw/OpenAI)
- [SwiftOpenAI Package](https://github.com/jamesrochabrun/SwiftOpenAI)

## Appendix B: Current Verso Reads Architecture (For Reference)

**What we have today:**
- `OpenAIClient.swift` — OpenAI Responses API with SSE streaming (text only, no tool calls)
- `RAGStore.swift` — SQLite + sqlite-vec vector database (1536-dim embeddings)
- `RAGIngestionManager.swift` — PDF → chunks → embeddings pipeline
- `RAGQueryService.swift` — Embed query → vector search → return chunks
- `RAGChunker.swift` — 1200-char chunks with 200-char overlap
- `ChatView.swift` — Chat UI with streaming markdown, always-RAG on every message
- `Annotation.swift` — SwiftData model for highlights, notes, chat pins
- `DocumentNote.swift` — Per-document Tiptap editor notes
- Model: `gpt-5.2` (hardcoded in `OpenAISettingsStore`)

**What we extend:**
- `OpenAIClient` — add tool call event parsing
- `ChatView` — replace direct streaming with `AgentRunner`

**What we add:**
- `AgentRunner` — the agentic while loop
- `ToolExecutor` — dispatches tool calls to handlers
- `AgentTool` — tool definition struct
- Tool handlers for each capability
