//
//  ChatSessionManager.swift
//  verso-reads
//

import Foundation
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class ChatSessionManager {
    var currentSession: ChatSession?
    var currentIndex: Int = 0
    var totalSessions: Int = 0

    private var sessions: [ChatSession] = []
    private var documentID: UUID?
    private weak var modelContext: ModelContext?

    var canGoBack: Bool { currentIndex > 0 }
    var canGoForward: Bool { currentIndex < totalSessions - 1 }

    var counterText: String {
        guard totalSessions > 0 else { return "" }
        return "\(currentIndex + 1) / \(totalSessions)"
    }

    func attach(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Load sessions for a document and navigate to the most recent one.
    /// Returns the messages for the current session.
    func loadDocument(_ documentID: UUID) -> [ChatMessage] {
        self.documentID = documentID
        reloadSessions()

        if sessions.isEmpty {
            return startNewSession()
        }

        currentIndex = sessions.count - 1
        currentSession = sessions[currentIndex]
        return loadMessages(for: currentSession!)
    }

    func goBack() -> [ChatMessage] {
        guard canGoBack else { return [] }
        currentIndex -= 1
        currentSession = sessions[currentIndex]
        return loadMessages(for: currentSession!)
    }

    func goForward() -> [ChatMessage] {
        guard canGoForward else { return [] }
        currentIndex += 1
        currentSession = sessions[currentIndex]
        return loadMessages(for: currentSession!)
    }

    @discardableResult
    func startNewSession() -> [ChatMessage] {
        guard let documentID, let modelContext else { return [] }

        let session = ChatSession(documentID: documentID)
        modelContext.insert(session)
        try? modelContext.save()

        reloadSessions()
        currentIndex = sessions.count - 1
        currentSession = session
        return []
    }

    func persistMessage(_ message: ChatMessage, documentID: UUID) {
        guard let modelContext, let sessionID = currentSession?.id else { return }

        let record = ChatMessageRecord(
            id: message.id,
            documentID: documentID,
            chatSessionID: sessionID,
            role: message.role,
            content: message.content
        )
        modelContext.insert(record)
        try? modelContext.save()
    }

    func persistAssistantMessage(id: UUID, documentID: UUID, messages: [ChatMessage]) {
        guard let modelContext, let sessionID = currentSession?.id else { return }
        guard let message = messages.first(where: { $0.id == id }) else { return }
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        let record = ChatMessageRecord(
            id: message.id,
            documentID: documentID,
            chatSessionID: sessionID,
            role: message.role,
            content: message.content
        )
        modelContext.insert(record)
        try? modelContext.save()
    }

    func clear() {
        currentSession = nil
        currentIndex = 0
        totalSessions = 0
        sessions = []
        documentID = nil
    }

    // MARK: - Private

    private func reloadSessions() {
        guard let modelContext, let documentID else {
            sessions = []
            totalSessions = 0
            return
        }

        let descriptor = FetchDescriptor<ChatSession>(
            predicate: #Predicate<ChatSession> { $0.documentID == documentID },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        sessions = (try? modelContext.fetch(descriptor)) ?? []
        totalSessions = sessions.count
    }

    private func loadMessages(for session: ChatSession) -> [ChatMessage] {
        guard let modelContext else { return [] }

        let sessionID = session.id
        let descriptor = FetchDescriptor<ChatMessageRecord>(
            predicate: #Predicate<ChatMessageRecord> { $0.chatSessionID == sessionID },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )

        let records = (try? modelContext.fetch(descriptor)) ?? []
        return records.map { record in
            ChatMessage(
                id: record.id,
                role: record.roleRawValue == "user" ? .user : .assistant,
                content: record.content
            )
        }
    }
}
