//
//  OpenAISettingsStore.swift
//  verso-reads
//

import Foundation
import Combine

@MainActor
final class OpenAISettingsStore: ObservableObject {
    @Published var apiKey: String = ""
    @Published var model: String = "gpt-5.2"
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
        do {
            if let storedKey = try KeychainStore.read(service: keychainService, account: keychainAccount) {
                apiKey = storedKey
            }
        } catch {
            statusMessage = "Could not read API key."
        }

        if let storedModel = UserDefaults.standard.string(forKey: modelDefaultsKey),
           storedModel.isEmpty == false {
            model = storedModel
        } else {
            model = "gpt-5.2"
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
            UserDefaults.standard.set(trimmedModel.isEmpty ? "gpt-5.2" : trimmedModel, forKey: modelDefaultsKey)
            model = trimmedModel.isEmpty ? "gpt-5.2" : trimmedModel
            statusMessage = "Saved."
            scheduleStatusClearIfNeeded()
        } catch {
            statusMessage = "Unable to save key."
        }
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
