//
//  ToolDefinition.swift
//  verso-reads
//

import Foundation

struct ToolDefinition {
    let name: String
    let description: String
    let parameters: [String: Any]

    func toJSON() -> [String: Any] {
        [
            "type": "function",
            "name": name,
            "description": description,
            "parameters": parameters,
            "strict": true
        ]
    }
}

enum AgentTools {
    static let all: [ToolDefinition] = [
        searchDocument,
        readHighlights,
        readNotes,
        getDocumentInfo,
        getCurrentPage,
        getPageText,
        navigateToPage,
        createNote,
        appendToNote,
        createHighlight,
        deleteHighlight,
        updateHighlight,
        undoLastAction
    ]

    static let searchDocument = ToolDefinition(
        name: "search_document",
        description: "Search the current document for passages relevant to a query. Use this when you need specific information from the document text and don't already have it in the conversation context.",
        parameters: [
            "type": "object",
            "properties": [
                "query": [
                    "type": "string",
                    "description": "Natural language search query to find relevant passages in the document"
                ]
            ],
            "required": ["query"],
            "additionalProperties": false
        ]
    )

    static let readHighlights = ToolDefinition(
        name: "read_highlights",
        description: "Fetch all highlights and annotations the user has made on the current document. Returns a list with each highlight's ID, quoted text, color, and page number.",
        parameters: [
            "type": "object",
            "properties": [String: Any](),
            "required": [String](),
            "additionalProperties": false
        ]
    )

    static let readNotes = ToolDefinition(
        name: "read_notes",
        description: "Fetch the user's notepad content for the current document. Returns the plain text content of their notes.",
        parameters: [
            "type": "object",
            "properties": [String: Any](),
            "required": [String](),
            "additionalProperties": false
        ]
    )

    static let getDocumentInfo = ToolDefinition(
        name: "get_document_info",
        description: "Get metadata about the current document: title, author, page count, and file type.",
        parameters: [
            "type": "object",
            "properties": [String: Any](),
            "required": [String](),
            "additionalProperties": false
        ]
    )

    static let getCurrentPage = ToolDefinition(
        name: "get_current_page",
        description: "Get the page number the user is currently viewing in the document.",
        parameters: [
            "type": "object",
            "properties": [String: Any](),
            "required": [String](),
            "additionalProperties": false
        ]
    )

    static let getPageText = ToolDefinition(
        name: "get_page_text",
        description: "Extract the full text content of a specific page in the document. Useful for reading or summarizing a particular page.",
        parameters: [
            "type": "object",
            "properties": [
                "page": [
                    "type": "number",
                    "description": "The page number to extract text from (1-based)"
                ]
            ],
            "required": ["page"],
            "additionalProperties": false
        ]
    )

    static let navigateToPage = ToolDefinition(
        name: "navigate_to_page",
        description: "Scroll the document view to a specific page. Use this when the user asks to go to a page or when referencing content on a particular page.",
        parameters: [
            "type": "object",
            "properties": [
                "page": [
                    "type": "number",
                    "description": "The page number to navigate to (1-based)"
                ]
            ],
            "required": ["page"],
            "additionalProperties": false
        ]
    )

    static let createNote = ToolDefinition(
        name: "create_note",
        description: "Create a new note for the current document. Only works if no note exists yet — if one already exists, use append_to_note instead.",
        parameters: [
            "type": "object",
            "properties": [
                "text": [
                    "type": "string",
                    "description": "The text content to write as the note"
                ]
            ],
            "required": ["text"],
            "additionalProperties": false
        ]
    )

    static let appendToNote = ToolDefinition(
        name: "append_to_note",
        description: "Append text to the end of the user's existing notes for this document. Creates the note if it doesn't exist yet. Use this to add summaries, key points, or any content the user asks you to note down.",
        parameters: [
            "type": "object",
            "properties": [
                "text": [
                    "type": "string",
                    "description": "The text content to append to the notes"
                ]
            ],
            "required": ["text"],
            "additionalProperties": false
        ]
    )

    static let createHighlight = ToolDefinition(
        name: "create_highlight",
        description: "Highlight a passage in the document. The quote must be an exact or near-exact substring of the text on the specified page. When highlighting a topic, first use search_document to find relevant passages, then highlight each one.",
        parameters: [
            "type": "object",
            "properties": [
                "quote": [
                    "type": "string",
                    "description": "The exact text to highlight. Must match the document text closely."
                ],
                "page": [
                    "type": "number",
                    "description": "The page number where the text appears (1-based)"
                ],
                "color": [
                    "type": "string",
                    "enum": ["yellow", "orange", "green", "blue"],
                    "description": "Highlight color"
                ]
            ],
            "required": ["quote", "page", "color"],
            "additionalProperties": false
        ]
    )

    static let deleteHighlight = ToolDefinition(
        name: "delete_highlight",
        description: "Remove an existing highlight by its ID. Use read_highlights first to get the list of highlight IDs.",
        parameters: [
            "type": "object",
            "properties": [
                "id": [
                    "type": "string",
                    "description": "The UUID of the highlight to delete"
                ]
            ],
            "required": ["id"],
            "additionalProperties": false
        ]
    )

    static let updateHighlight = ToolDefinition(
        name: "update_highlight",
        description: "Change the color of an existing highlight. Use read_highlights first to get the highlight ID.",
        parameters: [
            "type": "object",
            "properties": [
                "id": [
                    "type": "string",
                    "description": "The UUID of the highlight to update"
                ],
                "color": [
                    "type": "string",
                    "enum": ["yellow", "orange", "green", "blue"],
                    "description": "The new highlight color"
                ]
            ],
            "required": ["id", "color"],
            "additionalProperties": false
        ]
    )

    static let undoLastAction = ToolDefinition(
        name: "undo_last_action",
        description: "Undo all highlights created during this conversation turn. Use this when the user says something like 'undo that', 'remove those highlights', or 'nevermind'.",
        parameters: [
            "type": "object",
            "properties": [String: Any](),
            "required": [String](),
            "additionalProperties": false
        ]
    )
}
