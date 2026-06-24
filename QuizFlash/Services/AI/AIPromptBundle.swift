//
//  AIPromptBundle.swift
//  QuizFlash
//

import CryptoKit
import Foundation

nonisolated enum AIPromptTemplateKey {
    static let cardTypeFlashcard = "cardType.flashcard"
    static let cardTypeQuiz = "cardType.quiz"
    static let depthPro = "depth.pro"
    static let depthSimple = "depth.simple"
    static let languageAuto = "language.auto"
    static let languageLocked = "language.locked"
    static let layoutFlashcard = "layout.flashcard"
    static let layoutQuiz = "layout.quiz"
    static let rulesFlashcard = "rules.flashcard"
    static let rulesQuiz = "rules.quiz"
    static let schemaFlashcard = "schema.flashcard"
    static let schemaQuiz = "schema.quiz"
    static let sourceTruncated = "source.truncated"
    static let systemBase = "system.base"
    static let systemOCR = "system.ocr"
    static let titleSystem = "title.system"
    static let titleUser = "title.user"
    static let userTextBase = "user.text.base"
    static let userTextCoveredHeader = "user.text.covered.header"
    static let userTextCoveredItem = "user.text.covered.item"
    static let userTextFlashcard = "user.text.flashcard"
    static let userTextLanguage = "user.text.language"
    static let userTextQuiz = "user.text.quiz"
    static let userTextRepeat = "user.text.repeat"
    static let userTextSource = "user.text.source"
    static let userVisionBase = "user.vision.base"
    static let userVisionCoveredHeader = "user.vision.covered.header"
    static let userVisionCoveredItem = "user.vision.covered.item"
    static let userVisionFlashcard = "user.vision.flashcard"
    static let userVisionLanguage = "user.vision.language"
    static let userVisionQuiz = "user.vision.quiz"
    static let userVisionRepeat = "user.vision.repeat"

    static let required: Set<String> = [
        cardTypeFlashcard,
        cardTypeQuiz,
        depthPro,
        depthSimple,
        languageAuto,
        languageLocked,
        layoutFlashcard,
        layoutQuiz,
        rulesFlashcard,
        rulesQuiz,
        schemaFlashcard,
        schemaQuiz,
        sourceTruncated,
        systemBase,
        systemOCR,
        titleSystem,
        titleUser,
        userTextBase,
        userTextCoveredHeader,
        userTextCoveredItem,
        userTextFlashcard,
        userTextLanguage,
        userTextQuiz,
        userTextRepeat,
        userTextSource,
        userVisionBase,
        userVisionCoveredHeader,
        userVisionCoveredItem,
        userVisionFlashcard,
        userVisionLanguage,
        userVisionQuiz,
        userVisionRepeat
    ]
}

nonisolated struct AIPromptBundle: Codable, Equatable, Sendable {
    let version: String
    let hash: String
    let status: String
    let templates: [String: String]

    static let requiredTemplateKeys = AIPromptTemplateKey.required

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
    static let cacheKey = "quizflash.ai.promptBundle.v1"

    private let defaults: UserDefaults
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
        defaults.set(data, forKey: Self.cacheKey)
        inMemoryBundle = validated
        return validated
    }

    static func loadStoredBundleSynchronously(defaults: UserDefaults = .standard) -> AIPromptBundle? {
        guard let data = defaults.data(forKey: cacheKey),
              let bundle = try? JSONDecoder().decode(AIPromptBundle.self, from: data),
              let validated = try? bundle.validated() else {
            return nil
        }
        return validated
    }

    private func loadStoredBundle() -> AIPromptBundle? {
        if let inMemoryBundle {
            return inMemoryBundle
        }
        guard let validated = Self.loadStoredBundleSynchronously(defaults: defaults) else {
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
