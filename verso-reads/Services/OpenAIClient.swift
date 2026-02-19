//
//  OpenAIClient.swift
//  verso-reads
//

import Foundation

struct OpenAIClient {
    let apiKey: String
    let model: String
    var session: URLSession = .shared

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
                                debugLog("Delta +\(delta.count) chars")
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
