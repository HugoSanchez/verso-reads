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

    private let apiKeyDefaultsKey = "openai.api-key"
    private let modelDefaultsKey = "openai.model"
    private let migratedDefaultsKey = "openai.migrated-from-keychain"
    private var statusClearTask: Task<Void, Never>?

    var hasAPIKey: Bool {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func load() {
        // In development, check environment variable or .env file first
        if let devKey = OpenAISettingsStore.devAPIKey() {
            apiKey = devKey
        } else {
            // Migrate from Keychain on first run (so existing users don't lose their key)
            migrateFromKeychainIfNeeded()

            if let storedKey = UserDefaults.standard.string(forKey: apiKeyDefaultsKey),
               storedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                apiKey = storedKey
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

        if trimmedKey.isEmpty {
            UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey)
        } else {
            UserDefaults.standard.set(trimmedKey, forKey: apiKeyDefaultsKey)
        }
        UserDefaults.standard.set(trimmedModel.isEmpty ? "gpt-5.2-mini" : trimmedModel, forKey: modelDefaultsKey)
        model = trimmedModel.isEmpty ? "gpt-5.2-mini" : trimmedModel

        statusMessage = "Saved."
        scheduleStatusClearIfNeeded()
    }

    /// One-time migration: copy the API key from Keychain to UserDefaults, then delete the Keychain entry.
    private func migrateFromKeychainIfNeeded() {
        guard UserDefaults.standard.bool(forKey: migratedDefaultsKey) == false else { return }
        UserDefaults.standard.set(true, forKey: migratedDefaultsKey)

        let bundleID = Bundle.main.bundleIdentifier ?? "verso-reads"
        let service = "\(bundleID).openai"
        let account = "openai-api-key"

        if let keychainKey = try? KeychainStore.read(service: service, account: account),
           keychainKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            UserDefaults.standard.set(keychainKey, forKey: apiKeyDefaultsKey)
            try? KeychainStore.delete(service: service, account: account)
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

    /// Read the API key directly from UserDefaults (for use outside the settings store, e.g. RAG ingestion).
    static func storedAPIKey() -> String? {
        if let devKey = devAPIKey() { return devKey }
        if let key = UserDefaults.standard.string(forKey: "openai.api-key"),
           key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return key
        }
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
