//
//  AIPromptBundle.swift
//  QuizFlash
//

import CryptoKit
import Foundation

nonisolated struct AIPromptBundle: Codable, Equatable, Sendable {
    let version: String
    let hash: String
    let status: String
    let templates: [String: String]

    static let requiredTemplateKeys: Set<String> = [
        "schema.flashcard",
        "schema.quiz",
        "system.base",
        "title.system",
        "title.user"
    ]

    func validated() throws -> AIPromptBundle {
        guard !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !hash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIServiceError.unknown("AI prompt configuration is invalid.")
        }

        let missingKeys = Self.requiredTemplateKeys.filter {
            (templates[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard missingKeys.isEmpty else {
            throw AIServiceError.unknown("AI prompt configuration is missing required templates.")
        }

        let canonicalHash = try Self.hashTemplates(templates)
        guard canonicalHash == hash else {
            throw AIServiceError.unknown("AI prompt configuration hash does not match.")
        }

        return self
    }

    func template(_ key: String) throws -> String {
        guard let value = templates[key], !value.isEmpty else {
            throw AIServiceError.unknown("AI prompt configuration is missing template \(key).")
        }
        return value
    }

    static func hashTemplates(_ templates: [String: String]) throws -> String {
        let data = try makeAIPromptBundleEncoder().encode(templates)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

actor AIPromptBundleCache {
    static let shared = AIPromptBundleCache()

    private let defaults: UserDefaults
    private let cacheKey = "quizflash.ai.promptBundle.v1"
    private let decoder = JSONDecoder()
    private var inMemoryBundle: AIPromptBundle?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func knownPromptVersion() -> String? {
        if let inMemoryBundle {
            return inMemoryBundle.version
        }
        return loadStoredBundle()?.version
    }

    func bundle(version: String, hash: String) throws -> AIPromptBundle {
        guard let bundle = loadStoredBundle(),
              bundle.version == version,
              bundle.hash == hash else {
            throw AIServiceError.unknown("AI prompt configuration is unavailable.")
        }
        return try bundle.validated()
    }

    func store(_ bundle: AIPromptBundle) throws -> AIPromptBundle {
        let validated = try bundle.validated()
        let data = try makeAIPromptBundleEncoder().encode(validated)
        defaults.set(data, forKey: cacheKey)
        inMemoryBundle = validated
        return validated
    }

    private func loadStoredBundle() -> AIPromptBundle? {
        if let inMemoryBundle {
            return inMemoryBundle
        }
        guard let data = defaults.data(forKey: cacheKey),
              let bundle = try? decoder.decode(AIPromptBundle.self, from: data),
              let validated = try? bundle.validated() else {
            return nil
        }
        inMemoryBundle = validated
        return validated
    }
}

private nonisolated func makeAIPromptBundleEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
}
