//
//  CloudAIGenerationService.swift
//  QuizFlash
//

import FirebaseFunctions
import Foundation

// MARK: - Cloud AI Generation Service

/// Calls the Firebase backend for production AI generation.
final class CloudAIGenerationService: @unchecked Sendable {
    private let functions: Functions
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(functions: Functions = Functions.functions()) {
        self.functions = functions
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    /// Generates validated draft card content from source text through Cloud Functions.
    func generateDeck(
        text: String,
        targetCards: Int,
        options: AIGenerationOptions
    ) async throws -> CloudGeneratedDeck {
        let result = try await functions.httpsCallable("generateDeck").call([
            "source": [
                "kind": "text",
                "text": text
            ],
            "targetCards": targetCards,
            "options": optionsPayload(from: options)
        ])

        guard let object = result.data as? [String: Any] else {
            throw CloudAIGenerationError.invalidResponse
        }

        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        let response = try decoder.decode(CloudGenerateDeckResponse.self, from: data)
        let cards = try response.cards.map { try $0.draftCardContent() }

        return CloudGeneratedDeck(
            deckID: response.deckID,
            title: response.title,
            cards: cards,
            freeGenerationsUsed: response.freeGenerationsUsed,
            freeGenerationsLimit: response.freeGenerationsLimit
        )
    }

    private func optionsPayload(from options: AIGenerationOptions) -> [String: Any] {
        var payload: [String: Any] = [
            "cardType": options.cardType.rawValue,
            "cardLevel": options.cardLevel.rawValue,
            "sourceDistributionMode": options.sourceDistributionMode.rawValue,
            "outputLanguageMode": options.outputLanguageMode.rawValue
        ]

        if let manualOutputLanguage = options.manualOutputLanguage {
            payload["manualOutputLanguage"] = [
                "languageCode": manualOutputLanguage.languageCode,
                "displayName": manualOutputLanguage.displayName
            ]
        }

        if let sourceLanguageHint = options.sourceLanguageHint {
            payload["sourceLanguageHint"] = [
                "languageCode": sourceLanguageHint.languageCode,
                "displayName": sourceLanguageHint.displayName
            ]
        }

        return payload
    }
}

// MARK: - Cloud Generated Deck

struct CloudGeneratedDeck: Sendable {
    let deckID: String
    let title: String?
    let cards: [DraftCardContent]
    let freeGenerationsUsed: Int?
    let freeGenerationsLimit: Int?
}

private struct CloudGenerateDeckResponse: Decodable {
    let deckID: String
    let title: String?
    let cards: [DeckJSONCardDTO]
    let freeGenerationsUsed: Int?
    let freeGenerationsLimit: Int?
}

enum CloudAIGenerationError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The cloud AI response was invalid."
        }
    }
}
