//
//  ConversationCompressor.swift
//  verso-reads
//

import Foundation
import os

private let log = Logger(subsystem: "com.verso.agent", category: "compressor")

struct ConversationCompressor {
    /// Approximate token limit for conversation history sent to the API.
    /// We compress when the estimated token count exceeds this.
    private static let tokenBudget = 12_000

    /// We keep the most recent N messages uncompressed for immediate context.
    private static let recentWindowSize = 6

    /// Rough token estimate: ~4 chars per token for English text.
    static func estimateTokens(for text: String) -> Int {
        max(1, text.count / 4)
    }

    static func estimateTokens(for messages: [OpenAIClient.Message]) -> Int {
        messages.reduce(0) { $0 + estimateTokens(for: $1.content) + 4 }
    }

    /// Build conversation messages with compression if needed.
    /// Returns messages ready to send to the API.
    static func buildConversation(
        from history: [ChatMessage],
        userPrompt: String,
        client: OpenAIClient
    ) async -> [OpenAIClient.Message] {
        let nonEmpty = history.filter {
            $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }

        let allMessages = nonEmpty.map { message -> OpenAIClient.Message in
            OpenAIClient.Message(
                role: message.role == .user ? "user" : "assistant",
                content: message.content
            )
        }

        let currentUserMessage = OpenAIClient.Message(role: "user", content: userPrompt)
        let totalTokens = estimateTokens(for: allMessages) + estimateTokens(for: userPrompt)

        // If under budget, send everything
        if totalTokens <= tokenBudget {
            log.debug("Under token budget (\(totalTokens)/\(Self.tokenBudget)), sending all \(allMessages.count) messages")
            return allMessages + [currentUserMessage]
        }

        log.debug("Over token budget (\(totalTokens)/\(Self.tokenBudget)), compressing \(allMessages.count) messages")

        // Split into older messages (to compress) and recent messages (to keep)
        let recentCount = min(recentWindowSize, allMessages.count)
        let olderMessages = Array(allMessages.dropLast(recentCount))
        let recentMessages = Array(allMessages.suffix(recentCount))

        guard olderMessages.isEmpty == false else {
            return allMessages + [currentUserMessage]
        }

        // Summarize older messages
        let summary = await summarize(messages: olderMessages, client: client)

        if let summary {
            log.debug("Compressed \(olderMessages.count) older messages into summary (\(summary.count) chars)")
            let summaryMessage = OpenAIClient.Message(
                role: "user",
                content: "[Conversation summary from earlier messages]\n\(summary)"
            )
            return [summaryMessage] + recentMessages + [currentUserMessage]
        } else {
            // Summarization failed — fall back to truncating older messages
            log.warning("Summarization failed, falling back to recent messages only")
            return recentMessages + [currentUserMessage]
        }
    }

    private static func summarize(messages: [OpenAIClient.Message], client: OpenAIClient) async -> String? {
        let transcript = messages.map { msg in
            let role = msg.role == "user" ? "User" : "Assistant"
            return "\(role): \(msg.content)"
        }.joined(separator: "\n\n")

        let prompt = """
        Summarize this conversation concisely. Focus on:
        - Key questions the user asked
        - Important findings or answers
        - Any actions taken (highlights created, notes written, papers found)
        - Document-specific context that would be needed to continue the conversation

        Keep the summary under 300 words. Write in third person ("The user asked about...", "The assistant found...").

        Conversation:
        \(transcript)
        """

        do {
            var result = ""
            let stream = client.streamResponse(
                systemPrompt: "You are a concise summarizer. Output only the summary, nothing else.",
                userPrompt: prompt
            )
            for try await delta in stream {
                result += delta
            }
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            log.error("Summarization error: \(error.localizedDescription)")
            return nil
        }
    }
}
