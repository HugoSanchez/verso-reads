//
//  AgentLoop.swift
//  verso-reads
//

import Foundation
import os

private let loopLog = Logger(subsystem: "com.verso.agent", category: "loop")
private let toolLog = Logger(subsystem: "com.verso.agent", category: "tool")

enum AgentEvent {
    case textDelta(String)
    case toolCallStarted(String)
    case toolCallCompleted(String)
    case completed
    case error(Error)
}

struct AgentLoop {
    let client: OpenAIClient
    let systemPrompt: String
    let tools: [ToolDefinition]
    let toolExecutor: ToolExecutor

    private let maxIterations = 10

    static func buildSystemPrompt(documentTitle: String) -> String {
        """
        You are a reading assistant for Verso Reads, helping the user with "\(documentTitle)".

        ## When to use tools
        - search_document: When the user asks about specific content in the document and you don't already have relevant context in the conversation. Do NOT search if the question is about text already provided as context (e.g. selected text).
        - read_highlights: When the user asks about their existing highlights or annotations.
        - read_notes: When the user asks about or references their scratchpad.
        - get_document_info: When you need document metadata (title, author, page count).
        - get_current_page: When you need to know what page the user is viewing.
        - get_page_text: When you need the full text of a specific page.
        - navigate_to_page: When the user asks to go to a specific page or you want to direct them to relevant content.
        - create_note: When the user asks you to write or create a note from scratch. This replaces existing scratchpad content.
        - append_to_note: When the user asks you to add something to their scratchpad. Prefer this over create_note to avoid overwriting existing content.
        - create_highlight: When the user asks to highlight text. IMPORTANT: First use search_document or get_page_text to find the exact text, then use the exact quote from the document. Do not paraphrase or modify the text.
        - delete_highlight: When the user asks to remove a highlight. Use read_highlights first to find the ID.
        - update_highlight: When the user asks to change a highlight's color. Use read_highlights first to find the ID.
        - undo_last_action: When the user wants to undo highlights you just created in this turn (e.g. "undo that", "remove those").
        - search_all_documents: When the user asks about connections between documents, wants to find something across their library, or references content not in the current document.
        - get_library: When the user asks what documents they have, or you need to understand their reading list.
        - get_collections: When the user asks about their collections or how their reading is organized.
        - get_chat_history: When the user references a prior conversation or asks "what did we discuss about X?"
        - search_arxiv: When the user asks to find academic papers, search for related work, or wants to know what's been published on a topic. Returns paper metadata and abstracts.
        - search_semantic_scholar: Similar to search_arxiv but includes citation counts and venue info. Prefer this when the user cares about paper impact or wants well-established papers.
        - search_pubmed: When the user asks about medical, biological, health, or life sciences research. PubMed covers biomedical literature that arXiv and Semantic Scholar may not have. NOTE: PubMed papers cannot be downloaded into the library — if the user asks, let them know this isn't supported yet.
        - download_paper: When the user asks to download, save, or add a paper to their library. IMPORTANT: Always confirm with the user before downloading — tell them the paper title and ask if they want to add it.
        - add_to_collection: When the user asks to organize a document into a collection. Creates the collection if it doesn't exist.
        - Web search is available automatically — you can search the web for general information, recent news, or to supplement academic searches. Use it when other search tools fail or when the user asks about something beyond academic papers.

        ## Guidelines
        - Be concise. Synthesize search results — don't dump raw text.
        - If you don't have enough context to answer a question about the document, use search_document.
        - Reference specific pages when possible.
        - When writing to the scratchpad, use clear formatting with line breaks between sections.
        - Prefer append_to_note over create_note unless the user explicitly asks to start fresh.
        - IMPORTANT: If a tool call fails or returns an error, tell the user honestly that you couldn't access the information and suggest they try again or share the relevant text. Do NOT make up generic answers or provide information that isn't from the actual document. Only answer based on content you have actually retrieved or been given.
        """
    }

    func run(messages: [OpenAIClient.Message]) -> AsyncThrowingStream<AgentEvent, Error> {
        let toolDefs = tools.map { $0.toJSON() }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var previousResponseId: String? = nil
                    var currentInput: [[String: Any]]? = nil
                    var iteration = 0

                    loopLog.debug("Starting run with \(messages.count) messages, \(self.tools.count) tools")

                    while iteration < maxIterations {
                        iteration += 1
                        loopLog.debug("Iteration \(iteration)/\(self.maxIterations)")

                        let stream: AsyncThrowingStream<OpenAIClient.SSEEvent, Error>

                        if let prevId = previousResponseId, let toolResults = currentInput {
                            // Continuation after tool execution
                            stream = client.streamAgentResponse(
                                systemPrompt: systemPrompt,
                                messages: [],
                                tools: toolDefs,
                                previousResponseId: prevId,
                                toolResults: toolResults
                            )
                        } else {
                            // First request
                            stream = client.streamAgentResponse(
                                systemPrompt: systemPrompt,
                                messages: messages,
                                tools: toolDefs,
                                previousResponseId: nil,
                                toolResults: nil
                            )
                        }

                        // Collect tool calls from this response
                        var pendingCalls: [Int: PendingToolCall] = [:]
                        var responseId: String = ""
                        var hasToolCalls = false

                        for try await event in stream {
                            switch event {
                            case .textDelta(let text):
                                continuation.yield(.textDelta(text))

                            case .functionCallStarted(let callId, let name, let index):
                                loopLog.debug("Function call started: \(name) (call_id: \(callId))")
                                pendingCalls[index] = PendingToolCall(callId: callId, name: name, arguments: "")
                                hasToolCalls = true
                                continuation.yield(.toolCallStarted(name))

                            case .functionCallArgumentsDelta(let index, let delta):
                                pendingCalls[index]?.arguments += delta

                            case .functionCallArgumentsDone(let index, let arguments):
                                pendingCalls[index]?.arguments = arguments
                                if let call = pendingCalls[index] {
                                    loopLog.debug("Function call arguments done: \(call.name) -> \(arguments.prefix(200))")
                                }

                            case .hostedToolCompleted(let name):
                                loopLog.debug("Hosted tool completed: \(name)")
                                continuation.yield(.toolCallCompleted(name))

                            case .responseCompleted(let id):
                                responseId = id
                                loopLog.debug("Response completed (id: \(id))")

                            case .error(let error):
                                loopLog.error("SSE error: \(error.localizedDescription)")
                                continuation.yield(.error(error))
                                continuation.finish()
                                return

                            case .done:
                                break
                            }
                        }

                        // If no tool calls, we're done
                        guard hasToolCalls else {
                            loopLog.debug("Completed after \(iteration) iteration(s) (no tool calls)")
                            continuation.yield(.completed)
                            continuation.finish()
                            return
                        }

                        // Execute tool calls
                        let sortedCalls = pendingCalls.sorted { $0.key < $1.key }
                        toolLog.debug("Executing \(sortedCalls.count) tool call(s)")

                        var toolResults: [[String: Any]] = []
                        for (_, call) in sortedCalls {
                            let result = await toolExecutor.execute(name: call.name, arguments: call.arguments)
                            toolResults.append([
                                "type": "function_call_output",
                                "call_id": call.callId,
                                "output": result
                            ])
                            continuation.yield(.toolCallCompleted(call.name))
                        }

                        toolLog.debug("Sending \(toolResults.count) tool result(s) with previous_response_id: \(responseId)")
                        previousResponseId = responseId
                        currentInput = toolResults
                    }

                    loopLog.warning("Max iterations (\(self.maxIterations)) reached")
                    continuation.yield(.completed)
                    continuation.finish()

                } catch {
                    loopLog.error("Agent loop error: \(error.localizedDescription)")
                    continuation.yield(.error(error))
                    continuation.finish()
                }
            }
        }
    }
}

private struct PendingToolCall {
    let callId: String
    let name: String
    var arguments: String
}
