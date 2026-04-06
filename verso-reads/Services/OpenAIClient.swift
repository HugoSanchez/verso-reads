//
//  OpenAIClient.swift
//  verso-reads
//

import Foundation

struct OpenAIClient {
    let apiKey: String
    let model: String
    var session: URLSession = .shared

    struct Message {
        let role: String
        let content: String
    }

    func streamResponse(systemPrompt: String, userPrompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    debugLog("Starting stream. model=\(model) promptChars=\(userPrompt.count)")
                    let request = try buildRequest(systemPrompt: systemPrompt, userPrompt: userPrompt)
                    let (bytes, response) = try await session.bytes(for: request)

                    if let httpResponse = response as? HTTPURLResponse,
                       (200...299).contains(httpResponse.statusCode) == false {
                        debugLog("HTTP status \(httpResponse.statusCode)")
                        var data = Data()
                        for try await byte in bytes {
                            data.append(byte)
                        }
                        let message = String(data: data, encoding: .utf8)
                        debugLog("HTTP error body: \(message ?? "nil")")
                        continuation.finish(throwing: OpenAIClientError.httpStatus(httpResponse.statusCode, message))
                        return
                    }

                    if let httpResponse = response as? HTTPURLResponse {
                        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                        debugLog("HTTP status \(httpResponse.statusCode) content-type=\(contentType)")
                    }

                    var parser = SSEParser()
                    var lineCount = 0
                    var eventCount = 0
                    for try await line in bytes.lines {
                        lineCount += 1
                        if lineCount <= 20 {
                            debugLog("SSE line \(lineCount): \(line)")
                        }
                        for event in parser.ingest(line: line) {
                            eventCount += 1
                            if eventCount <= 10 {
                                debugLog("SSE event \(eventCount): \(event.prefix(200))")
                            }
                            if event == "[DONE]" {
                                continuation.finish()
                                return
                            }
                            if let delta = parseDelta(from: event) {
                                continuation.yield(delta)
                            } else if let error = parseError(from: event) {
                                debugLog("SSE error: \(error.localizedDescription)")
                                continuation.finish(throwing: error)
                                return
                            } else if isCompletedEvent(event) {
                                debugLog("SSE completed event")
                                continuation.finish()
                                return
                            } else if let type = eventType(from: event), eventCount <= 10 {
                                debugLog("SSE event type: \(type)")
                            }
                        }
                    }

                    debugLog("Stream ended without completion event")
                    continuation.finish()
                } catch {
                    debugLog("Stream error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func streamResponse(systemPrompt: String, messages: [Message]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let totalChars = messages.reduce(0) { $0 + $1.content.count }
                    debugLog("Starting stream. model=\(model) messageChars=\(totalChars)")
                    let request = try buildRequest(systemPrompt: systemPrompt, messages: messages)
                    let (bytes, response) = try await session.bytes(for: request)

                    if let httpResponse = response as? HTTPURLResponse,
                       (200...299).contains(httpResponse.statusCode) == false {
                        debugLog("HTTP status \(httpResponse.statusCode)")
                        var data = Data()
                        for try await byte in bytes {
                            data.append(byte)
                        }
                        let message = String(data: data, encoding: .utf8)
                        debugLog("HTTP error body: \(message ?? "nil")")
                        continuation.finish(throwing: OpenAIClientError.httpStatus(httpResponse.statusCode, message))
                        return
                    }

                    if let httpResponse = response as? HTTPURLResponse {
                        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                        debugLog("HTTP status \(httpResponse.statusCode) content-type=\(contentType)")
                    }

                    var parser = SSEParser()
                    for try await line in bytes.lines {
                        for event in parser.ingest(line: line) {
                            if event == "[DONE]" {
                                continuation.finish()
                                return
                            }
                            if let delta = parseDelta(from: event) {
                                continuation.yield(delta)
                            } else if let error = parseError(from: event) {
                                debugLog("SSE error: \(error.localizedDescription)")
                                continuation.finish(throwing: error)
                                return
                            } else if isCompletedEvent(event) {
                                debugLog("SSE completed event")
                                continuation.finish()
                                return
                            }
                        }
                    }

                    debugLog("Stream ended without completion event")
                    continuation.finish()
                } catch {
                    debugLog("Stream error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func createEmbeddings(input: [String], model: String) async throws -> [[Float]] {
        let request = try buildEmbeddingsRequest(input: input, model: model)
        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           (200...299).contains(httpResponse.statusCode) == false {
            let message = String(data: data, encoding: .utf8)
            throw OpenAIClientError.httpStatus(httpResponse.statusCode, message)
        }

        let decoded = try JSONDecoder().decode(EmbeddingsResponse.self, from: data)
        let sorted = decoded.data.sorted { $0.index < $1.index }
        return sorted.map { $0.embedding.map { Float($0) } }
    }

    private func buildRequest(systemPrompt: String, userPrompt: String) throws -> URLRequest {
        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw OpenAIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let input: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]

        let body: [String: Any] = [
            "model": model,
            "input": input,
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    private func buildRequest(systemPrompt: String, messages: [Message]) throws -> URLRequest {
        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw OpenAIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let mapped = messages.map { ["role": $0.role, "content": $0.content] }
        let input: [[String: Any]] = [["role": "system", "content": systemPrompt]] + mapped

        let body: [String: Any] = [
            "model": model,
            "input": input,
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    private func buildEmbeddingsRequest(input: [String], model: String) throws -> URLRequest {
        guard let url = URL(string: "https://api.openai.com/v1/embeddings") else {
            throw OpenAIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "input": input,
            "encoding_format": "float"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    private func parseDelta(from data: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any] else {
            return nil
        }
        guard let type = object["type"] as? String else { return nil }
        guard type == "response.output_text.delta" else { return nil }
        return object["delta"] as? String
    }

    private func parseError(from data: String) -> Error? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any] else {
            return nil
        }
        if let type = object["type"] as? String, type == "error" {
            let message = (object["error"] as? [String: Any])?["message"] as? String
            return OpenAIClientError.apiError(message ?? "OpenAI error")
        }
        return nil
    }

    private func isCompletedEvent(_ data: String) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any] else {
            return false
        }
        return (object["type"] as? String) == "response.completed"
    }

    private func eventType(from data: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any] else {
            return nil
        }
        return object["type"] as? String
    }

    // MARK: - Agent Streaming (with tool use)

    enum SSEEvent {
        case textDelta(String)
        case functionCallStarted(callId: String, name: String, index: Int)
        case functionCallArgumentsDelta(index: Int, delta: String)
        case functionCallArgumentsDone(index: Int, arguments: String)
        case hostedToolCompleted(name: String)
        case responseCompleted(responseId: String)
        case error(Error)
        case done
    }

    func streamAgentResponse(
        systemPrompt: String,
        messages: [Message],
        tools: [[String: Any]],
        previousResponseId: String?,
        toolResults: [[String: Any]]?
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try buildAgentRequest(
                        systemPrompt: systemPrompt,
                        messages: messages,
                        tools: tools,
                        previousResponseId: previousResponseId,
                        toolResults: toolResults
                    )
                    let (bytes, response) = try await session.bytes(for: request)

                    if let httpResponse = response as? HTTPURLResponse,
                       (200...299).contains(httpResponse.statusCode) == false {
                        var data = Data()
                        for try await byte in bytes {
                            data.append(byte)
                        }
                        let message = String(data: data, encoding: .utf8)
                        sseLog("HTTP error \(httpResponse.statusCode): \(message ?? "nil")")
                        continuation.finish(throwing: OpenAIClientError.httpStatus(httpResponse.statusCode, message))
                        return
                    }

                    if let httpResponse = response as? HTTPURLResponse {
                        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                        sseLog("HTTP status \(httpResponse.statusCode) content-type=\(contentType)")
                    }

                    var parser = SSEParser()
                    for try await line in bytes.lines {
                        for eventData in parser.ingest(line: line) {
                            if eventData == "[DONE]" {
                                continuation.yield(.done)
                                continuation.finish()
                                return
                            }
                            if let sseEvent = parseSSEEvent(from: eventData) {
                                continuation.yield(sseEvent)
                                if case .responseCompleted = sseEvent {
                                    continuation.finish()
                                    return
                                }
                                if case .error = sseEvent {
                                    continuation.finish()
                                    return
                                }
                            }
                        }
                    }

                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    sseLog("Stream error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func buildAgentRequest(
        systemPrompt: String,
        messages: [Message],
        tools: [[String: Any]],
        previousResponseId: String?,
        toolResults: [[String: Any]]?
    ) throws -> URLRequest {
        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw OpenAIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "tools": tools
        ]

        if let prevId = previousResponseId, let results = toolResults {
            // Continuation: send tool results with previous response reference
            body["previous_response_id"] = prevId
            body["input"] = results
            sseLog("Building continuation request with \(results.count) tool result(s), previous_response_id=\(prevId)")
        } else {
            // Initial request: send full conversation
            let mapped = messages.map { ["role": $0.role, "content": $0.content] }
            let input: [[String: Any]] = [["role": "system", "content": systemPrompt]] + mapped
            body["input"] = input
            sseLog("Building initial request with \(messages.count) messages")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    private func parseSSEEvent(from data: String) -> SSEEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
              let type = object["type"] as? String else {
            return nil
        }

        switch type {
        case "response.output_text.delta":
            if let delta = object["delta"] as? String {
                return .textDelta(delta)
            }

        case "response.output_item.added":
            if let item = object["item"] as? [String: Any] {
                let itemType = item["type"] as? String ?? ""
                if itemType == "function_call" {
                    let callId = item["call_id"] as? String ?? ""
                    let name = item["name"] as? String ?? ""
                    let index = object["output_index"] as? Int ?? 0
                    sseLog("Function call started: \(name) (call_id: \(callId), index: \(index))")
                    return .functionCallStarted(callId: callId, name: name, index: index)
                } else if itemType == "web_search_call" {
                    sseLog("Web search started")
                    return .functionCallStarted(callId: "__web_search__", name: "web_search", index: -1)
                }
            }

        case "response.web_search_call.completed":
            sseLog("Web search completed")
            return .hostedToolCompleted(name: "web_search")

        case "response.function_call_arguments.delta":
            let index = object["output_index"] as? Int ?? 0
            let delta = object["delta"] as? String ?? ""
            return .functionCallArgumentsDelta(index: index, delta: delta)

        case "response.function_call_arguments.done":
            let index = object["output_index"] as? Int ?? 0
            let arguments = object["arguments"] as? String ?? ""
            sseLog("Function call arguments done (index: \(index)): \(arguments.prefix(200))")
            return .functionCallArgumentsDone(index: index, arguments: arguments)

        case "response.completed":
            let responseId = (object["response"] as? [String: Any])?["id"] as? String ?? ""
            sseLog("Response completed (id: \(responseId))")
            return .responseCompleted(responseId: responseId)

        case "error":
            let msg = (object["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
            sseLog("Error event: \(msg)")
            return .error(OpenAIClientError.apiError(msg))

        default:
            break
        }

        return nil
    }

    private func sseLog(_ message: String) {
        #if DEBUG
        print("[agent.sse] \(message)")
        #endif
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[OpenAIClient] \(message)")
        #endif
    }
}

private struct SSEParser {
    mutating func ingest(line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }

        if trimmed.hasPrefix("data:") {
            let data = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            return data.isEmpty ? [] : [String(data)]
        }
        return []
    }
}

enum OpenAIClientError: LocalizedError {
    case invalidURL
    case httpStatus(Int, String?)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid OpenAI URL."
        case .httpStatus(let code, let message):
            return "OpenAI error (\(code)): \(message ?? "Unknown response")."
        case .apiError(let message):
            return message
        }
    }
}

private struct EmbeddingsResponse: Decodable {
    struct EmbeddingData: Decodable {
        let embedding: [Double]
        let index: Int
    }

    let data: [EmbeddingData]
}
