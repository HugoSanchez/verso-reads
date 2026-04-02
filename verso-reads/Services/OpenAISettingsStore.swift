//
//  OpenAISettingsStore.swift
//  verso-reads
//

import Foundation
import Combine

@MainActor
final class OpenAISettingsStore: ObservableObject {
    @Published var apiKey: String = ""
    @Published var model: String = "gpt-5.2-mini"
    @Published var statusMessage: String?

    private let keychainService: String
    private let keychainAccount = "openai-api-key"
    private let modelDefaultsKey = "openai.model"
    private var statusClearTask: Task<Void, Never>?

    init(service: String? = nil) {
        let bundleID = Bundle.main.bundleIdentifier ?? "verso-reads"
        self.keychainService = service ?? "\(bundleID).openai"
    }

    var hasAPIKey: Bool {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func load() {
        // In development, check environment variable or .env file first to avoid Keychain password prompts
        if let devKey = OpenAISettingsStore.devAPIKey() {
            apiKey = devKey
        } else {
            do {
                if let storedKey = try KeychainStore.read(service: keychainService, account: keychainAccount) {
                    apiKey = storedKey
                }
            } catch {
                statusMessage = "Could not read API key."
            }
        }

        if let storedModel = UserDefaults.standard.string(forKey: modelDefaultsKey),
           storedModel.isEmpty == false {
            model = storedModel
        } else {
            model = "gpt-5.2-mini"
        }
    }

    func save() {
        statusClearTask?.cancel()
        statusClearTask = nil

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if trimmedKey.isEmpty {
                try KeychainStore.delete(service: keychainService, account: keychainAccount)
            } else {
                try KeychainStore.save(trimmedKey, service: keychainService, account: keychainAccount)
            }
            UserDefaults.standard.set(trimmedModel.isEmpty ? "gpt-5.2-mini" : trimmedModel, forKey: modelDefaultsKey)
            model = trimmedModel.isEmpty ? "gpt-5.2-mini" : trimmedModel
            statusMessage = "Saved."
            scheduleStatusClearIfNeeded()
        } catch {
            statusMessage = "Unable to save key."
        }
    }

    /// Check for API key in environment variable or .env file (for development convenience).
    static func devAPIKey() -> String? {
        // 1. Check environment variable (set via Xcode scheme)
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
           envKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return envKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 2. Check .env file in the project source root
        #if DEBUG
        if let sourceRoot = ProcessInfo.processInfo.environment["SRCROOT"] ?? Bundle.main.resourceURL?.deletingLastPathComponent().path {
            let envFilePath = (sourceRoot as NSString).appendingPathComponent(".env")
            if let contents = try? String(contentsOfFile: envFilePath, encoding: .utf8) {
                for line in contents.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("OPENAI_API_KEY=") {
                        let value = String(trimmed.dropFirst("OPENAI_API_KEY=".count))
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        if !value.isEmpty { return value }
                    }
                }
            }
        }
        #endif

        return nil
    }

    private func scheduleStatusClearIfNeeded() {
        guard statusMessage == "Saved." else { return }

        statusClearTask?.cancel()
        statusClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                self?.statusMessage = nil
            }
        }
    }
}
