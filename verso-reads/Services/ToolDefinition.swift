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
        readNotes
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
}
