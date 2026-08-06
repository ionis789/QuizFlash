import Foundation
import UIKit // Required for UIImage – image pipeline only, no UI components used

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

nonisolated struct SourceProfileResponseDTO: Codable {
    let deck_title: String?
    let language_code: String?
    let language_display_name: String?
}

nonisolated struct AISourceGenerationProfile: Equatable, Sendable {
    let deckTitle: String?
    let languageHint: AIGenerationLanguageHint?
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
    let transport: AIRequestTransport
    let session: URLSession
    let debugTraceStore: AIDebugTraceStore
    let promptBundle: AIPromptBundle?
    let promptCacheStatus: String?
    let maxCharsPerChunk = 12_000
    let maxConcurrentTextPlanRequests = 6
    let maxConcurrentVisionPlanRequests = 4
    let timeoutIntervalForRequest: TimeInterval = 360
    let timeoutIntervalForResource: TimeInterval = 1_800
    let maxRequestRetryCount = 4
    let baseRetryDelayNanoseconds: UInt64 = 1_200_000_000
    let maxRetryDelayNanoseconds: UInt64 = 12_000_000_000

    var apiEndpoint: URL? {
        switch transport {
        case .directProvider:
            return provider.resolvedRequestURL
        case .cloudProxy(let generation):
            return generation.baseURL.appending(path: "v1/chat/completions")
        }
    }
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
        nonisolated var serializationKey: String? { get }
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
        let blueprintContext: AIBlueprintBatchContext?
        let serializationKey: String?

        func splitForRecovery() -> [TextBatchPlan]? {
            guard targetCards > 1 else { return nil }
            let left = max(1, targetCards / 2)
            let right = targetCards - left
            let splitCounts = right > 0 ? [left, right] : [left]
            var objectiveOffset = 0
            return splitCounts.map { count in
                let splitContext = blueprintContext.map { context in
                    let objectives = Array(context.objectives.dropFirst(objectiveOffset).prefix(count))
                    objectiveOffset += objectives.count
                    return AIBlueprintBatchContext(
                        globalOutline: context.globalOutline,
                        theme: context.theme,
                        objectives: objectives
                    )
                }
                return TextBatchPlan(
                    text: text,
                    sourceLabel: sourceLabel,
                    allocationID: allocationID,
                    targetCards: count,
                    batchIndex: batchIndex,
                    totalBatches: totalBatches,
                    passIndex: passIndex,
                    blueprintContext: splitContext,
                    serializationKey: serializationKey
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
        let serializationKey: String? = nil

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

    struct GeneratedBatchExecutionResult {
        let cards: [AIFlashcard]
        let shortfallCount: Int
    }

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    init(
        provider: AIProviderProfile,
        transport: AIRequestTransport = .directProvider,
        debugTraceStore: AIDebugTraceStore = .shared,
        promptBundle: AIPromptBundle? = nil
    ) {
        self.provider = provider
        self.transport = transport
        self.debugTraceStore = debugTraceStore
        self.promptBundle = promptBundle ?? transport.promptBundle
        self.promptCacheStatus = transport.promptCacheStatus
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutIntervalForRequest
        config.timeoutIntervalForResource = timeoutIntervalForResource
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
    }

    // -------------------------------------------------------------------------
}
