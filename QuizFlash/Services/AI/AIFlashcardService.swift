import Foundation
import UIKit // Required for UIImage – image pipeline only, no UI components used
import SwiftData

// =============================================================================
// MARK: - AI Service Errors
// =============================================================================

public enum AIServiceError: LocalizedError {
    case invalidAPIKey
    case networkError
    case invalidResponse
    case parsingFailed
    case rateLimitExceeded
    case timeout
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAPIKey: return "Invalid API key."
        case .networkError: return "Network error."
        case .invalidResponse: return "Invalid response."
        case .parsingFailed: return "Parsing failed."
        case .rateLimitExceeded: return "Too many requests. Try again later."
        case .timeout: return "Timeout – no response from the server."
        case .unknown(let msg): return msg
        }
    }
}

// =============================================================================
// MARK: - Response DTO
// =============================================================================

/// The structured JSON contract between GPT and the app for flashcard output.
nonisolated struct FlashcardResponseDTO: Codable {
    struct CardDTO: Codable {
        let question_zones: [String]?
        let question: String? // Fallback if question_zones are intepreted as question by AI
        let answer_zones: [String]
        let answer: [String]? // Fallback

        var resolvedQuestionZones: [String] {
            if let qz = question_zones { return qz }
            if let q = question { return [q] }
            return ["?"]
        }
    }
    let cards: [CardDTO]?
    let flashcards: [CardDTO]?

    var resolvedCards: [CardDTO] {
        cards ?? flashcards ?? []
    }
}

/// The structured JSON contract between GPT and the app for quiz output.
nonisolated struct QuizResponseDTO: Codable {
    struct CardDTO: Codable {
        let question_zones: [String]
        let choices: [String]
        let correct_indexes: [Int]
        let explanation_zones: [String]?
    }

    let cards: [CardDTO]
}

/// The structured JSON contract between GPT and the app for dedicated match output.
nonisolated struct MatchResponseDTO: Codable {
    struct CardDTO: Codable {
        let prompt: String
        let answer: String
    }

    let cards: [CardDTO]
}

/// The structured JSON contract between GPT and the app for write output.
nonisolated struct WriteResponseDTO: Codable {
    struct CardDTO: Codable {
        let source_text: String
        let omitted_text: String
    }

    let cards: [CardDTO]
}

/// Structured conversion result for flashcard targets, keyed by source index.
nonisolated struct FlashcardConversionResponseDTO: Codable {
    struct ResultDTO: Codable {
        let source_index: Int
        let question_zones: [String]
        let answer_zones: [String]
    }

    let results: [ResultDTO]
}

/// Structured conversion result for dedicated match targets, keyed by source index.
nonisolated struct MatchConversionResponseDTO: Codable {
    struct ResultDTO: Codable {
        let source_index: Int
        let prompt: String
        let answer: String
    }

    let results: [ResultDTO]
}

/// Structured conversion result for quiz targets, keyed by source index.
nonisolated struct QuizConversionResponseDTO: Codable {
    struct ResultDTO: Codable {
        let source_index: Int
        let question_zones: [String]
        let choices: [String]
        let correct_indexes: [Int]
        let explanation_zones: [String]?
    }

    let results: [ResultDTO]
}

/// Structured conversion result for write targets, keyed by source index.
nonisolated struct WriteConversionResponseDTO: Codable {
    struct ResultDTO: Codable {
        let source_index: Int
        let source_text: String
        let omitted_text: String
    }

    let results: [ResultDTO]
}

nonisolated struct DeckTitleResponseDTO: Codable {
    let deck_title: String?
}

nonisolated struct AIProviderErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String?
        let type: String?
        let param: String?
        let code: String?
    }

    let error: APIError?
}

// =============================================================================
// MARK: - AI Flashcard Service
// =============================================================================

public final class AIFlashcardService: @unchecked Sendable {

    // -------------------------------------------------------------------------
    // MARK: - Configuration
    // -------------------------------------------------------------------------

    let provider: AIProviderProfile
    let session: URLSession
    let debugTraceStore: AIDebugTraceStore
    let maxCharsPerChunk = 12_000
    let maxConcurrentTextPlanRequests = 6
    let maxConcurrentVisionPlanRequests = 4
    let maxConcurrentConversionRequests = 6
    let maxConcurrentMatchGenerationRequests = 3
    let maxConcurrentMatchConversionRequests = 3
    let timeoutIntervalForRequest: TimeInterval = 360
    let timeoutIntervalForResource: TimeInterval = 1_800
    let conversionBatchExecutionTimeoutNanoseconds: UInt64 = 120_000_000_000
    let maxRequestRetryCount = 4
    let maxMatchQualityAttempts = 2
    let baseRetryDelayNanoseconds: UInt64 = 1_200_000_000
    let maxRetryDelayNanoseconds: UInt64 = 12_000_000_000

    var apiEndpoint: URL? { provider.resolvedRequestURL }
    var textModel: String { provider.trimmedTextModel }
    var visionModel: String { provider.trimmedVisionModel }

    struct RetriableRequestError: Error {
        let serviceError: AIServiceError
        let retryAfter: TimeInterval?
    }

    struct TextSourceUnit {
        let content: String
        let label: String
    }

    protocol RecoverableBatchPlan: Sendable {
        nonisolated var targetCards: Int { get }
        nonisolated var sourceLabel: String { get }
        nonisolated func splitForRecovery() -> [Self]?
    }

    struct TextBatchPlan: RecoverableBatchPlan {
        let text: String
        let sourceLabel: String
        let allocationID: UUID?
        let targetCards: Int
        let batchIndex: Int
        let totalBatches: Int
        let passIndex: Int

        func splitForRecovery() -> [TextBatchPlan]? {
            guard targetCards > 1 else { return nil }
            let left = max(1, targetCards / 2)
            let right = targetCards - left
            let splitCounts = right > 0 ? [left, right] : [left]
            return splitCounts.map { count in
                TextBatchPlan(
                    text: text,
                    sourceLabel: sourceLabel,
                    allocationID: allocationID,
                    targetCards: count,
                    batchIndex: batchIndex,
                    totalBatches: totalBatches,
                    passIndex: passIndex
                )
            }
        }
    }

    struct VisionBatchPlan: RecoverableBatchPlan, @unchecked Sendable {
        let images: [UIImage]
        let sourceLabel: String
        let allocationID: UUID?
        let targetCards: Int
        let batchIndex: Int
        let totalBatches: Int
        let passIndex: Int

        func splitForRecovery() -> [VisionBatchPlan]? {
            guard targetCards > 1 else { return nil }
            let left = max(1, targetCards / 2)
            let right = targetCards - left
            let splitCounts = right > 0 ? [left, right] : [left]
            return splitCounts.map { count in
                VisionBatchPlan(
                    images: images,
                    sourceLabel: sourceLabel,
                    allocationID: allocationID,
                    targetCards: count,
                    batchIndex: batchIndex,
                    totalBatches: totalBatches,
                    passIndex: passIndex
                )
            }
        }
    }

    struct ConversionBatchPlan: RecoverableBatchPlan {
        let sourceCards: [AICardConversionSource]
        let sourceLabel: String
        let targetCards: Int
        let batchIndex: Int
        let totalBatches: Int

        func splitForRecovery() -> [ConversionBatchPlan]? {
            guard sourceCards.count > 1 else { return nil }

            let midpoint = max(1, sourceCards.count / 2)
            let leftCards = Array(sourceCards[..<midpoint])
            let rightCards = Array(sourceCards[midpoint...])

            return [
                ConversionBatchPlan(
                    sourceCards: leftCards,
                    sourceLabel: "\(sourceLabel) A",
                    targetCards: leftCards.count,
                    batchIndex: batchIndex,
                    totalBatches: totalBatches
                ),
                ConversionBatchPlan(
                    sourceCards: rightCards,
                    sourceLabel: "\(sourceLabel) B",
                    targetCards: rightCards.count,
                    batchIndex: batchIndex,
                    totalBatches: totalBatches
                )
            ]
            .filter { !$0.sourceCards.isEmpty }
        }
    }

    struct MatchGenerationQualityResult {
        let cards: [AIFlashcard]
        let shortfallCount: Int
        let diagnostics: MatchAIBatchDiagnostics
    }

    struct MatchConversionQualityResult {
        let outputs: [AICardConversionOutput]
        let shortfallCount: Int
        let diagnostics: MatchAIBatchDiagnostics
    }

    struct WriteConversionQualityResult {
        let outputs: [AICardConversionOutput]
        let shortfallCount: Int
    }

    struct MatchConversionFilterResult {
        let outputs: [AICardConversionOutput]
        let rejectedSourceIDs: Set<PersistentIdentifier>
        let retryHints: [String]
        let diagnostics: MatchAIBatchDiagnostics
        let feedbackLines: [String]
    }

    struct WriteConversionFilterResult {
        let outputs: [AICardConversionOutput]
        let rejectedSourceIDs: Set<PersistentIdentifier>
        let retryHints: [String]
    }

    struct GeneratedBatchExecutionResult {
        let cards: [AIFlashcard]
        let shortfallCount: Int
        let matchDiagnostics: MatchAIBatchDiagnostics?
    }

    enum MatchAIShortfallReason: String, Codable, Sendable, Hashable {
        case structurallyRejected
        case duplicatePair
        case invalidSourceMapping
        case providerUnderfilled
        case exhaustedCandidates
    }

    struct MatchAIBatchDiagnostics: Sendable, Equatable {
        var lowQualityAcceptedCount: Int
        var shortfallReasonCounts: [MatchAIShortfallReason: Int]

        init(
            lowQualityAcceptedCount: Int = 0,
            shortfallReasonCounts: [MatchAIShortfallReason: Int] = [:]
        ) {
            self.lowQualityAcceptedCount = lowQualityAcceptedCount
            self.shortfallReasonCounts = shortfallReasonCounts
        }

        mutating func increment(
            _ reason: MatchAIShortfallReason,
            by count: Int = 1
        ) {
            guard count > 0 else { return }
            shortfallReasonCounts[reason, default: 0] += count
        }

        mutating func merge(_ other: MatchAIBatchDiagnostics) {
            lowQualityAcceptedCount += other.lowQualityAcceptedCount
            for (reason, count) in other.shortfallReasonCounts {
                shortfallReasonCounts[reason, default: 0] += count
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    init(
        provider: AIProviderProfile,
        debugTraceStore: AIDebugTraceStore = .shared
    ) {
        self.provider = provider
        self.debugTraceStore = debugTraceStore
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutIntervalForRequest
        config.timeoutIntervalForResource = timeoutIntervalForResource
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
    }

    // -------------------------------------------------------------------------
}
