//
//  RAGStore.swift
//  verso-reads
//

import Foundation
import SQLite3

@_silgen_name("verso_sqlite_vec_register")
private func verso_sqlite_vec_register() -> Int32

actor RAGStore {
    static let shared = RAGStore()

    enum RAGStoreError: LocalizedError {
        case invalidDatabaseURL
        case openFailed(String)
        case extensionLoadFailed(String)
        case statementPrepareFailed(String)
        case statementStepFailed(String)
        case invalidResult

        var errorDescription: String? {
            switch self {
            case .invalidDatabaseURL:
                return "Invalid database URL."
            case .openFailed(let message):
                return "Failed to open RAG database: \(message)"
            case .extensionLoadFailed(let message):
                return "Failed to load sqlite-vec extension: \(message)"
            case .statementPrepareFailed(let message):
                return "Failed to prepare database statement: \(message)"
            case .statementStepFailed(let message):
                return "Database operation failed: \(message)"
            case .invalidResult:
                return "Unexpected database result."
            }
        }
    }

    struct RAGChunkResult {
        let chunkIndex: Int
        let pageStart: Int?
        let pageEnd: Int?
        let text: String
        let distance: Double
    }

    private var db: OpaquePointer?
    private var didBootstrap = false
    private var didRegisterVec = false
    private let embeddingDimensions = 1536
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    func documentSignature(for documentID: UUID) async throws -> String? {
        try await openIfNeeded()
        try await bootstrapIfNeeded()

        let sql = "SELECT source_signature FROM rag_documents WHERE document_id = ? LIMIT 1;"
        let statement = try prepare(sql: sql)
        defer { sqlite3_finalize(statement) }

        bindText(statement, index: 1, value: documentID.uuidString)

        if sqlite3_step(statement) == SQLITE_ROW {
            guard let cString = sqlite3_column_text(statement, 0) else { return nil }
            return String(cString: cString)
        }
        return nil
    }

    func upsertDocument(_ document: LibraryDocument, signature: String) async throws {
        try await openIfNeeded()
        try await bootstrapIfNeeded()

        let sql = """
        INSERT INTO rag_documents (
            document_id, title, content_type, relative_path, source_signature, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(document_id) DO UPDATE SET
            title = excluded.title,
            content_type = excluded.content_type,
            relative_path = excluded.relative_path,
            source_signature = excluded.source_signature,
            updated_at = excluded.updated_at;
        """
        let statement = try prepare(sql: sql)
        defer { sqlite3_finalize(statement) }

        bindText(statement, index: 1, value: document.id.uuidString)
        bindText(statement, index: 2, value: document.title)
        bindText(statement, index: 3, value: document.contentTypeIdentifier)
        bindText(statement, index: 4, value: document.relativePath)
        bindText(statement, index: 5, value: signature)
        sqlite3_bind_double(statement, 6, document.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 7, Date().timeIntervalSince1970)

        try step(statement: statement)
    }

    func clearEmbeddings(for documentID: UUID) async throws {
        try await openIfNeeded()
        try await bootstrapIfNeeded()

        let sql = "DELETE FROM rag_embeddings WHERE document_id = ?;"
        let statement = try prepare(sql: sql)
        defer { sqlite3_finalize(statement) }

        bindText(statement, index: 1, value: documentID.uuidString)
        try step(statement: statement)
    }

    func insertEmbedding(
        documentID: UUID,
        chunkIndex: Int,
        pageStart: Int?,
        pageEnd: Int?,
        text: String,
        embeddingJSON: String
    ) async throws {
        try await openIfNeeded()
        try await bootstrapIfNeeded()

        let sql = """
        INSERT INTO rag_embeddings (
            document_id, chunk_index, page_start, page_end, embedding, text
        ) VALUES (?, ?, ?, ?, ?, ?);
        """
        let statement = try prepare(sql: sql)
        defer { sqlite3_finalize(statement) }

        bindText(statement, index: 1, value: documentID.uuidString)
        sqlite3_bind_int(statement, 2, Int32(chunkIndex))

        if let pageStart {
            sqlite3_bind_int(statement, 3, Int32(pageStart))
        } else {
            sqlite3_bind_null(statement, 3)
        }

        if let pageEnd {
            sqlite3_bind_int(statement, 4, Int32(pageEnd))
        } else {
            sqlite3_bind_null(statement, 4)
        }

        bindText(statement, index: 5, value: embeddingJSON)
        bindText(statement, index: 6, value: text)

        try step(statement: statement)
    }

    func searchSimilar(
        documentID: UUID,
        embeddingJSON: String,
        limit: Int
    ) async throws -> [RAGChunkResult] {
        try await openIfNeeded()
        try await bootstrapIfNeeded()

        let sql = """
        SELECT chunk_index, page_start, page_end, text, distance
        FROM rag_embeddings
        WHERE embedding MATCH ?
          AND k = ?
          AND document_id = ?;
        """
        let statement = try prepare(sql: sql)
        defer { sqlite3_finalize(statement) }

        bindText(statement, index: 1, value: embeddingJSON)
        sqlite3_bind_int(statement, 2, Int32(limit))
        bindText(statement, index: 3, value: documentID.uuidString)

        var results: [RAGChunkResult] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let chunkIndex = Int(sqlite3_column_int(statement, 0))
            let pageStart = sqlite3_column_type(statement, 1) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 1))
            let pageEnd = sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 2))
            let textPointer = sqlite3_column_text(statement, 3)
            let text = textPointer.map { String(cString: $0) } ?? ""
            let distance = sqlite3_column_double(statement, 4)
            results.append(
                RAGChunkResult(
                    chunkIndex: chunkIndex,
                    pageStart: pageStart,
                    pageEnd: pageEnd,
                    text: text,
                    distance: distance
                )
            )
        }
        return results
    }

    func deleteDocument(_ documentID: UUID) async throws {
        try await openIfNeeded()
        try await bootstrapIfNeeded()

        let sql = "DELETE FROM rag_documents WHERE document_id = ?;"
        let statement = try prepare(sql: sql)
        defer { sqlite3_finalize(statement) }

        bindText(statement, index: 1, value: documentID.uuidString)
        try step(statement: statement)

        try await clearEmbeddings(for: documentID)
    }

    private func openIfNeeded() async throws {
        if db != nil { return }

        guard let dbURL = databaseURL() else {
            throw RAGStoreError.invalidDatabaseURL
        }

        try await registerVecIfNeeded()

        var handle: OpaquePointer?
        let result = sqlite3_open(dbURL.path, &handle)
        guard result == SQLITE_OK, let openedHandle = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database."
            throw RAGStoreError.openFailed(message)
        }

        db = openedHandle
    }

    private func registerVecIfNeeded() async throws {
        guard didRegisterVec == false else { return }

        let result = await MainActor.run {
            verso_sqlite_vec_register()
        }
        guard result == SQLITE_OK else {
            throw RAGStoreError.extensionLoadFailed("sqlite3_auto_extension failed with code \(result).")
        }

        didRegisterVec = true
    }

    private func bootstrapIfNeeded() async throws {
        guard didBootstrap == false else { return }
        try await openIfNeeded()

        let createDocuments = """
        CREATE TABLE IF NOT EXISTS rag_documents (
            document_id TEXT PRIMARY KEY,
            title TEXT,
            content_type TEXT,
            relative_path TEXT,
            source_signature TEXT,
            created_at REAL,
            updated_at REAL
        );
        """

        let createEmbeddings = """
        CREATE VIRTUAL TABLE IF NOT EXISTS rag_embeddings USING vec0(
            chunk_id INTEGER PRIMARY KEY,
            embedding FLOAT[\(embeddingDimensions)],
            document_id TEXT,
            chunk_index INTEGER,
            page_start INTEGER,
            page_end INTEGER,
            +text TEXT
        );
        """

        try exec(sql: createDocuments)
        try exec(sql: createEmbeddings)
        didBootstrap = true
    }

    private func databaseURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "verso-reads"
        let root = appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("RAG", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("rag.sqlite3")
    }

    private func exec(sql: String) throws {
        guard let db else { return }
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw RAGStoreError.statementStepFailed(message)
        }
    }

    private func prepare(sql: String) throws -> OpaquePointer? {
        guard let db else { throw RAGStoreError.invalidDatabaseURL }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard result == SQLITE_OK else {
            throw RAGStoreError.statementPrepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        return statement
    }

    private func step(statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            guard let db else { throw RAGStoreError.invalidDatabaseURL }
            throw RAGStoreError.statementStepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func bindText(_ statement: OpaquePointer?, index: Int32, value: String) {
        sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, sqliteTransient)
    }
}
