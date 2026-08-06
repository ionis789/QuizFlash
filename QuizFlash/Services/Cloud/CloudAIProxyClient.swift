//
//  CloudAIProxyClient.swift
//  QuizFlash
//

import FirebaseAuth
import Foundation

nonisolated struct CloudAIGenerationSession: Sendable {
    let baseURL: URL
    let generationID: String
    let sessionToken: String
    let uid: String
    let targetCards: Int
    let quota: CloudAIQuotaState
    let promptBundle: AIPromptBundle
    let promptCacheStatus: String
}

nonisolated enum AIRequestTransport: Sendable {
    case directProvider
    case cloudProxy(CloudAIGenerationSession)

    var promptBundle: AIPromptBundle? {
        switch self {
        case .directProvider:
            return nil
        case .cloudProxy(let generation):
            return generation.promptBundle
        }
    }

    var promptCacheStatus: String? {
        switch self {
        case .directProvider:
            return nil
        case .cloudProxy(let generation):
            return generation.promptCacheStatus
        }
    }
}

nonisolated struct CloudAIQuotaState: Decodable, Sendable {
    let premium: Bool
    let freeGenerationsUsed: Int?
    let freeGenerationsLimit: Int?
    let monthlyCostMicroUSD: Int
    let limitMicroUSD: Int?
    let consumedMicroUSD: Int
    let reservedMicroUSD: Int
    let availableMicroUSD: Int?
    let percent: Double?
    let usageBasis: String?
    let billingWindowKey: String?
    let billingWindowStartMs: Int?
    let billingWindowEndMs: Int?

    var usageProgress: Double {
        guard let limitMicroUSD, limitMicroUSD > 0 else { return 0 }
        return min(1, Double(consumedMicroUSD + reservedMicroUSD) / Double(limitMicroUSD))
    }

    init(
        premium: Bool,
        freeGenerationsUsed: Int?,
        freeGenerationsLimit: Int?,
        monthlyCostMicroUSD: Int,
        limitMicroUSD: Int? = nil,
        consumedMicroUSD: Int? = nil,
        reservedMicroUSD: Int = 0,
        availableMicroUSD: Int? = nil,
        percent: Double? = nil,
        usageBasis: String? = nil,
        billingWindowKey: String? = nil,
        billingWindowStartMs: Int? = nil,
        billingWindowEndMs: Int? = nil
    ) {
        self.premium = premium
        self.freeGenerationsUsed = freeGenerationsUsed
        self.freeGenerationsLimit = freeGenerationsLimit
        self.monthlyCostMicroUSD = monthlyCostMicroUSD
        self.limitMicroUSD = limitMicroUSD
        self.consumedMicroUSD = consumedMicroUSD ?? monthlyCostMicroUSD
        self.reservedMicroUSD = reservedMicroUSD
        self.availableMicroUSD = availableMicroUSD
        self.percent = percent
        self.usageBasis = usageBasis
        self.billingWindowKey = billingWindowKey
        self.billingWindowStartMs = billingWindowStartMs
        self.billingWindowEndMs = billingWindowEndMs
    }

    enum CodingKeys: String, CodingKey {
        case premium
        case freeGenerationsUsed
        case freeGenerationsLimit
        case monthlyCostMicroUSD
        case limitMicroUSD
        case consumedMicroUSD
        case reservedMicroUSD
        case availableMicroUSD
        case percent
        case usageBasis
        case billingWindowKey
        case billingWindowStartMs
        case billingWindowEndMs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let monthlyCost = try container.decodeIfPresent(Int.self, forKey: .monthlyCostMicroUSD) ?? 0
        self.init(
            premium: try container.decode(Bool.self, forKey: .premium),
            freeGenerationsUsed: try container.decodeIfPresent(Int.self, forKey: .freeGenerationsUsed),
            freeGenerationsLimit: try container.decodeIfPresent(Int.self, forKey: .freeGenerationsLimit),
            monthlyCostMicroUSD: monthlyCost,
            limitMicroUSD: try container.decodeIfPresent(Int.self, forKey: .limitMicroUSD),
            consumedMicroUSD: try container.decodeIfPresent(Int.self, forKey: .consumedMicroUSD),
            reservedMicroUSD: try container.decodeIfPresent(Int.self, forKey: .reservedMicroUSD) ?? 0,
            availableMicroUSD: try container.decodeIfPresent(Int.self, forKey: .availableMicroUSD),
            percent: try container.decodeIfPresent(Double.self, forKey: .percent),
            usageBasis: try container.decodeIfPresent(String.self, forKey: .usageBasis),
            billingWindowKey: try container.decodeIfPresent(String.self, forKey: .billingWindowKey),
            billingWindowStartMs: try container.decodeIfPresent(Int.self, forKey: .billingWindowStartMs),
            billingWindowEndMs: try container.decodeIfPresent(Int.self, forKey: .billingWindowEndMs)
        )
    }
}

nonisolated struct CloudAIGenerationUsageRecord: Decodable, Identifiable, Sendable {
    let generationID: String
    let status: String
    let premium: Bool
    let targetCards: Int
    let validatedCards: Int
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let cacheHitTokens: Int
    let cacheMissTokens: Int
    let costMicroUSD: Int
    let createdAtMs: Int
    let completedAtMs: Int?

    var id: String { generationID }

    enum CodingKeys: String, CodingKey {
        case generationID = "generationId"
        case status
        case premium
        case targetCards
        case validatedCards
        case promptTokens
        case completionTokens
        case totalTokens
        case cacheHitTokens
        case cacheMissTokens
        case costMicroUSD
        case createdAtMs
        case completedAtMs
    }
}

/// Serializes cloud-session finalization with the next generation start.
@MainActor
final class CloudAIGenerationFinalizationCoordinator {
    typealias Operation = @MainActor @Sendable () async throws -> Void

    private struct PendingFinalization {
        let generationID: String
        let operation: Operation
    }

    private var pendingFinalization: PendingFinalization?
    private var activeTask: Task<Result<Void, Error>, Never>?

    /// Registers the server finalization synchronously, then starts it asynchronously.
    func register(
        generationID: String,
        operation: @escaping Operation
    ) -> Task<Result<Void, Error>, Never> {
        let pending = PendingFinalization(
            generationID: generationID,
            operation: operation
        )
        pendingFinalization = pending

        let task = Task { @MainActor [weak self] in
            guard let self else { return .success(()) }
            return await self.attempt(pending)
        }
        activeTask = task
        return task
    }

    /// Waits for an in-flight finalization and retries a retained failure once.
    func resolveBeforeStartingGeneration() async throws {
        if let activeTask {
            _ = await activeTask.value
        }
        guard let pendingFinalization else { return }
        try await attempt(pendingFinalization).get()
    }

    private func attempt(
        _ pending: PendingFinalization
    ) async -> Result<Void, Error> {
        do {
            try await pending.operation()
            if pendingFinalization?.generationID == pending.generationID {
                pendingFinalization = nil
            }
            activeTask = nil
            return .success(())
        } catch {
            activeTask = nil
            return .failure(error)
        }
    }
}

@MainActor
final class CloudAIProxyClient {
    static let shared = CloudAIProxyClient()

    private let session: URLSession
    private let generationFinalizationCoordinator: CloudAIGenerationFinalizationCoordinator

    init(
        session: URLSession = .shared,
        generationFinalizationCoordinator: CloudAIGenerationFinalizationCoordinator = .init()
    ) {
        self.session = session
        self.generationFinalizationCoordinator = generationFinalizationCoordinator
    }

    func prefetchPromptBundle() async {
        _ = try? await currentPromptBundle()
    }

    func currentUsageQuota() async throws -> CloudAIQuotaState {
        guard let user = Auth.auth().currentUser,
              let idToken = try? await user.getIDToken(),
              let baseURL = try? CloudAIProxyConfiguration.baseURL() else {
            await backendTrace(
                "entitlements-preflight-failed",
                layer: "cloud.ai-proxy"
            )
            throw CloudAIProxyError.signInRequired
        }

        var request = URLRequest(url: baseURL.appending(path: "v1/entitlements"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        await backendTrace(
            "entitlements-request-start",
            layer: "cloud.ai-proxy",
            details: [
                "uid": backendTraceSafeID(user.uid),
                "host": request.url?.host ?? "<none>",
                "path": request.url?.path ?? "<none>"
            ]
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            await backendTrace(
                "entitlements-invalid-response",
                layer: "cloud.ai-proxy"
            )
            throw CloudAIProxyError.invalidResponse
        }
        await backendTrace(
            "entitlements-response",
            layer: "cloud.ai-proxy",
            details: [
                "status": String(httpResponse.statusCode),
                "bytes": String(data.count)
            ]
        )
        guard (200...299).contains(httpResponse.statusCode) else {
            await backendTrace(
                "entitlements-error-response",
                layer: "cloud.ai-proxy",
                details: [
                    "status": String(httpResponse.statusCode),
                    "message": Self.errorMessage(from: data, fallbackStatus: httpResponse.statusCode)
                ]
            )
            throw CloudAIProxyError.response(message: Self.errorMessage(from: data, fallbackStatus: httpResponse.statusCode))
        }

        do {
            let quota = try JSONDecoder().decode(CloudAIQuotaState.self, from: data)
            await backendTrace(
                "entitlements-decode-success",
                layer: "cloud.ai-proxy",
                details: Self.quotaDetails(quota)
            )
            return quota
        } catch {
            await backendTrace(
                "entitlements-decode-error",
                layer: "cloud.ai-proxy",
                details: ["error": error.localizedDescription]
            )
            throw error
        }
    }

    func currentUsageGenerations() async throws -> [CloudAIGenerationUsageRecord] {
        guard let user = Auth.auth().currentUser,
              let idToken = try? await user.getIDToken(),
              let baseURL = try? CloudAIProxyConfiguration.baseURL() else {
            await backendTrace(
                "usage-generations-preflight-failed",
                layer: "cloud.ai-proxy"
            )
            throw CloudAIProxyError.signInRequired
        }

        var request = URLRequest(url: baseURL.appending(path: "v1/usage/generations"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        await backendTrace(
            "usage-generations-request-start",
            layer: "cloud.ai-proxy",
            details: [
                "uid": backendTraceSafeID(user.uid),
                "host": request.url?.host ?? "<none>",
                "path": request.url?.path ?? "<none>"
            ]
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            await backendTrace(
                "usage-generations-invalid-response",
                layer: "cloud.ai-proxy"
            )
            throw CloudAIProxyError.invalidResponse
        }
        await backendTrace(
            "usage-generations-response",
            layer: "cloud.ai-proxy",
            details: [
                "status": String(httpResponse.statusCode),
                "bytes": String(data.count)
            ]
        )
        guard (200...299).contains(httpResponse.statusCode) else {
            await backendTrace(
                "usage-generations-error-response",
                layer: "cloud.ai-proxy",
                details: [
                    "status": String(httpResponse.statusCode),
                    "message": Self.errorMessage(from: data, fallbackStatus: httpResponse.statusCode)
                ]
            )
            throw CloudAIProxyError.response(message: Self.errorMessage(from: data, fallbackStatus: httpResponse.statusCode))
        }

        do {
            let generations = try JSONDecoder().decode(UsageGenerationsResponse.self, from: data).generations
            await backendTrace(
                "usage-generations-decode-success",
                layer: "cloud.ai-proxy",
                details: Self.generationHistoryDetails(generations)
            )
            return generations
        } catch {
            await backendTrace(
                "usage-generations-decode-error",
                layer: "cloud.ai-proxy",
                details: ["error": error.localizedDescription]
            )
            throw error
        }
    }

    func currentPromptBundle() async throws -> AIPromptBundle {
        guard let user = Auth.auth().currentUser,
              let idToken = try? await user.getIDToken(),
              let baseURL = try? CloudAIProxyConfiguration.baseURL() else {
            throw CloudAIProxyError.signInRequired
        }

        let knownPromptVersion = await AIPromptBundleCache.shared.knownPromptVersion()
        var components = URLComponents(url: baseURL.appending(path: "v1/prompt-config"), resolvingAgainstBaseURL: false)
        if let knownPromptVersion {
            components?.queryItems = [URLQueryItem(name: "knownPromptVersion", value: knownPromptVersion)]
        }
        guard let url = components?.url else { throw CloudAIProxyError.configurationMissing }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIProxyError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw CloudAIProxyError.response(message: Self.errorMessage(from: data, fallbackStatus: httpResponse.statusCode))
        }

        let promptResponse = try JSONDecoder().decode(PromptConfigResponse.self, from: data)
        if let bundle = promptResponse.promptBundle {
            return try await AIPromptBundleCache.shared.store(bundle)
        }

        return try await AIPromptBundleCache.shared.bundle(
            version: promptResponse.promptVersion,
            hash: promptResponse.promptHash
        )
    }

    func startGeneration(targetCards: Int, idempotencyKey: UUID = UUID()) async throws -> CloudAIGenerationSession {
        try await generationFinalizationCoordinator.resolveBeforeStartingGeneration()
        guard let user = Auth.auth().currentUser else {
            throw CloudAIProxyError.signInRequired
        }
        let idToken = try await user.getIDToken()
        let baseURL = try CloudAIProxyConfiguration.baseURL()
        let knownPromptVersion = await AIPromptBundleCache.shared.knownPromptVersion()
        let response: StartResponse = try await sendJSON(
            endpoint: baseURL.appending(path: "v1/generations/start"),
            method: "POST",
            bearerToken: idToken,
            body: StartRequest(
                idempotencyKey: idempotencyKey.uuidString,
                targetCards: targetCards,
                knownPromptVersion: knownPromptVersion
            )
        )
        let promptBundle: AIPromptBundle
        let promptCacheStatus: String
        do {
            if let bundle = response.promptBundle {
                promptBundle = try await AIPromptBundleCache.shared.store(bundle)
                promptCacheStatus = "miss"
            } else {
                promptBundle = try await AIPromptBundleCache.shared.bundle(
                    version: response.promptVersion,
                    hash: response.promptHash
                )
                promptCacheStatus = "hit"
            }
        } catch {
            _ = try? await releaseGeneration(
                baseURL: baseURL,
                uid: user.uid,
                generationID: response.generationID,
                sessionToken: response.sessionToken
            )
            throw error
        }
        return CloudAIGenerationSession(
            baseURL: baseURL,
            generationID: response.generationID,
            sessionToken: response.sessionToken,
            uid: user.uid,
            targetCards: response.targetCards,
            quota: response.usageQuota,
            promptBundle: promptBundle,
            promptCacheStatus: promptCacheStatus
        )
    }

    func finishGeneration(_ generation: CloudAIGenerationSession, validatedCards: Int) async throws -> CloudAIQuotaState {
        let response: QuotaResponseEnvelope = try await sendJSON(
            endpoint: generation.baseURL.appending(path: "v1/generations/finish"),
            method: "POST",
            headers: ["X-QuizFlash-UID": generation.uid],
            body: FinishRequest(generationID: generation.generationID, sessionToken: generation.sessionToken, validatedCards: validatedCards)
        )
        SubscriptionManager.shared.applyCloudAIQuotaState(response.usageQuota)
        await SubscriptionManager.shared.refreshCloudAIGenerationHistory()
        return response.usageQuota
    }

    func failGeneration(_ generation: CloudAIGenerationSession) async {
        _ = try? await releaseGeneration(
            baseURL: generation.baseURL,
            uid: generation.uid,
            generationID: generation.generationID,
            sessionToken: generation.sessionToken
        )
    }

    /// Finalizes a successful or partial generation without allowing the next start to overtake it.
    func finalizeGeneration(
        _ generation: CloudAIGenerationSession,
        validatedCards: Int
    ) async {
        let task = registerGenerationFinalization(
            generation,
            validatedCards: validatedCards
        )
        _ = await task.value
    }

    /// Retains a completion request even when its caller must continue synchronously.
    func scheduleGenerationFinalization(
        _ generation: CloudAIGenerationSession,
        validatedCards: Int
    ) {
        _ = registerGenerationFinalization(
            generation,
            validatedCards: validatedCards
        )
    }

    /// Retains a failed-session release so a later start must wait for it.
    func scheduleGenerationFailure(_ generation: CloudAIGenerationSession) {
        let scope = AIDebugTraceContext.currentScope
        _ = generationFinalizationCoordinator.register(
            generationID: generation.generationID
        ) { [self] in
            await traceCloudFinalization(
                stage: .cloudFinalizationStarted,
                message: "Releasing failed cloud generation session.",
                generation: generation,
                scope: scope
            )
            do {
                _ = try await releaseGeneration(
                    baseURL: generation.baseURL,
                    uid: generation.uid,
                    generationID: generation.generationID,
                    sessionToken: generation.sessionToken
                )
                await traceCloudFinalization(
                    stage: .cloudFinalizationCompleted,
                    message: "Released failed cloud generation session.",
                    generation: generation,
                    scope: scope
                )
            } catch {
                await traceCloudFinalization(
                    stage: .cloudFinalizationFailed,
                    message: "Cloud generation release failed.",
                    generation: generation,
                    scope: scope,
                    metadata: ["error": error.localizedDescription]
                )
                throw error
            }
        }
    }

    private func registerGenerationFinalization(
        _ generation: CloudAIGenerationSession,
        validatedCards: Int
    ) -> Task<Result<Void, Error>, Never> {
        let scope = AIDebugTraceContext.currentScope
        return generationFinalizationCoordinator.register(
            generationID: generation.generationID
        ) { [self] in
            await traceCloudFinalization(
                stage: .cloudFinalizationStarted,
                message: "Finalizing cloud generation session.",
                generation: generation,
                scope: scope,
                metadata: ["validated_cards": String(validatedCards)]
            )
            do {
                _ = try await finishGeneration(
                    generation,
                    validatedCards: validatedCards
                )
                await traceCloudFinalization(
                    stage: .cloudFinalizationCompleted,
                    message: "Finalized cloud generation session.",
                    generation: generation,
                    scope: scope,
                    metadata: ["validated_cards": String(validatedCards)]
                )
            } catch {
                await traceCloudFinalization(
                    stage: .cloudFinalizationFailed,
                    message: "Cloud generation finalization failed.",
                    generation: generation,
                    scope: scope,
                    metadata: [
                        "validated_cards": String(validatedCards),
                        "error": error.localizedDescription
                    ]
                )
                throw error
            }
        }
    }

    private func traceCloudFinalization(
        stage: AIDebugTraceStage,
        message: String,
        generation: CloudAIGenerationSession,
        scope: AIDebugTraceScope?,
        metadata: [String: String] = [:]
    ) async {
        let traceMetadata = metadata.merging([
            "generation_id": backendTraceSafeID(generation.generationID)
        ]) { _, new in new }
        await backendTrace(
            stage.rawValue,
            layer: "cloud.ai-proxy",
            details: traceMetadata
        )
        await AIDebugTraceStore.shared.record(
            stage: stage,
            message: message,
            scope: scope,
            metadata: traceMetadata
        )
    }

    private func releaseGeneration(
        baseURL: URL,
        uid: String,
        generationID: String,
        sessionToken: String
    ) async throws -> CloudAIQuotaState {
        let response: QuotaResponseEnvelope = try await sendJSON(
            endpoint: baseURL.appending(path: "v1/generations/fail"),
            method: "POST",
            headers: ["X-QuizFlash-UID": uid],
            body: FailRequest(generationID: generationID, sessionToken: sessionToken)
        )
        SubscriptionManager.shared.applyCloudAIQuotaState(response.usageQuota)
        await SubscriptionManager.shared.refreshCloudAIGenerationHistory()
        return response.usageQuota
    }

    nonisolated static func prepareProviderRequest(
        _ request: inout URLRequest,
        generation: CloudAIGenerationSession,
        operation: String,
        providerCallID: UUID
    ) {
        request.url = generation.baseURL.appending(path: "v1/chat/completions")
        request.setValue(generation.generationID, forHTTPHeaderField: "X-QuizFlash-Generation-ID")
        request.setValue(generation.sessionToken, forHTTPHeaderField: "X-QuizFlash-Session")
        request.setValue(generation.uid, forHTTPHeaderField: "X-QuizFlash-UID")
        request.setValue(operation, forHTTPHeaderField: "X-QuizFlash-Operation")
        request.setValue(providerCallID.uuidString, forHTTPHeaderField: "X-QuizFlash-Provider-Call-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    nonisolated static func usageQuota(from response: HTTPURLResponse) -> CloudAIQuotaState? {
        guard let rawValue = response.value(forHTTPHeaderField: "X-QuizFlash-Usage-Quota"),
              let data = rawValue.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(CloudAIQuotaState.self, from: data)
    }

    private func sendJSON<Request: Encodable, Response: Decodable>(
        endpoint: URL,
        method: String,
        bearerToken: String? = nil,
        headers: [String: String] = [:],
        body: Request
    ) async throws -> Response {
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw CloudAIProxyError.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else {
            if let quota = Self.usageQuota(from: data) {
                SubscriptionManager.shared.applyCloudAIQuotaState(quota)
            }
            throw CloudAIProxyError.response(message: Self.errorMessage(from: data, fallbackStatus: httpResponse.statusCode))
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw CloudAIProxyError.invalidResponse
        }
    }

    private static func errorMessage(from data: Data, fallbackStatus: Int) -> String {
        guard let payload = try? JSONDecoder().decode(ProxyErrorEnvelope.self, from: data),
              let message = payload.error?.message,
              !message.isEmpty else {
            return "AI request failed (HTTP \(fallbackStatus))."
        }
        return message
    }

    private static func usageQuota(from data: Data) -> CloudAIQuotaState? {
        guard let payload = try? JSONDecoder().decode(QuotaResponseEnvelope.self, from: data) else {
            return nil
        }
        return payload.usageQuota
    }

    private static func quotaDetails(_ quota: CloudAIQuotaState) -> [String: String] {
        [
            "premium": String(quota.premium),
            "freeUsed": String(quota.freeGenerationsUsed ?? -1),
            "freeLimit": String(quota.freeGenerationsLimit ?? -1),
            "monthlyCostMicroUSD": String(quota.monthlyCostMicroUSD),
            "consumedMicroUSD": String(quota.consumedMicroUSD),
            "reservedMicroUSD": String(quota.reservedMicroUSD),
            "limitMicroUSD": String(quota.limitMicroUSD ?? -1),
            "availableMicroUSD": String(quota.availableMicroUSD ?? -1),
            "usageProgress": String(quota.usageProgress),
            "percent": String(quota.percent ?? -1),
            "usageBasis": quota.usageBasis ?? "unknown",
            "billingWindowKey": quota.billingWindowKey ?? "none",
            "billingWindowStartMs": String(quota.billingWindowStartMs ?? -1),
            "billingWindowEndMs": String(quota.billingWindowEndMs ?? -1)
        ]
    }

    private static func generationHistoryDetails(_ generations: [CloudAIGenerationUsageRecord]) -> [String: String] {
        let currentPeriod = periodKey(for: Date())
        let currentPeriodGenerations = generations.filter { generation in
            periodKey(forMilliseconds: generation.createdAtMs) == currentPeriod
        }
        let totalCost = generations.reduce(0) { $0 + max(0, $1.costMicroUSD) }
        let currentPeriodCost = currentPeriodGenerations.reduce(0) { $0 + max(0, $1.costMicroUSD) }
        let latestCreatedAtMs = generations.map(\.createdAtMs).max() ?? 0

        return [
            "count": String(generations.count),
            "currentPeriod": currentPeriod,
            "currentPeriodCount": String(currentPeriodGenerations.count),
            "currentPeriodCostMicroUSD": String(currentPeriodCost),
            "totalListedCostMicroUSD": String(totalCost),
            "latestCreatedAtMs": String(latestCreatedAtMs),
            "latestPeriod": periodKey(forMilliseconds: latestCreatedAtMs)
        ]
    }

    private static func periodKey(forMilliseconds milliseconds: Int) -> String {
        guard milliseconds > 0 else { return "<none>" }
        return periodKey(for: Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000))
    }

    private static func periodKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else { return "<none>" }
        return String(format: "%04d%02d", year, month)
    }
}

nonisolated enum CloudAIProxyConfiguration {
    static func baseURL(bundle: Bundle = .main) throws -> URL {
        guard let rawValue = bundle.object(forInfoDictionaryKey: "AIProxyBaseURL") as? String,
              let url = URL(string: rawValue),
              url.scheme == "https",
              url.host != nil,
              !rawValue.contains("REPLACE") else {
            throw CloudAIProxyError.configurationMissing
        }
        return url
    }
}

nonisolated enum CloudAIProxyError: LocalizedError {
    case signInRequired
    case configurationMissing
    case invalidResponse
    case response(message: String)

    var errorDescription: String? {
        switch self {
        case .signInRequired: return "Sign in is required."
        case .configurationMissing: return "AI service is not configured."
        case .invalidResponse: return "The AI service returned an invalid response."
        case .response(let message): return message
        }
    }
}

private struct StartRequest: Encodable {
    let idempotencyKey: String
    let targetCards: Int
    let knownPromptVersion: String?
}

struct StartResponse: Decodable {
    let generationID: String
    let sessionToken: String
    let targetCards: Int
    let usageQuota: CloudAIQuotaState
    let promptVersion: String
    let promptHash: String
    let promptBundle: AIPromptBundle?

    enum CodingKeys: String, CodingKey {
        case generationID = "generationId"
        case sessionToken, targetCards, quota, usageQuota, promptVersion, promptHash, promptBundle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generationID = try container.decode(String.self, forKey: .generationID)
        sessionToken = try container.decode(String.self, forKey: .sessionToken)
        targetCards = try container.decode(Int.self, forKey: .targetCards)
        usageQuota = try container.decodeIfPresent(CloudAIQuotaState.self, forKey: .usageQuota)
            ?? container.decode(CloudAIQuotaState.self, forKey: .quota)
        promptVersion = try container.decode(String.self, forKey: .promptVersion)
        promptHash = try container.decode(String.self, forKey: .promptHash)
        promptBundle = try container.decodeIfPresent(AIPromptBundle.self, forKey: .promptBundle)
    }
}

private struct QuotaResponseEnvelope: Decodable {
    let usageQuota: CloudAIQuotaState

    enum CodingKeys: String, CodingKey {
        case usageQuota
        case quota
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usageQuota = try container.decodeIfPresent(CloudAIQuotaState.self, forKey: .usageQuota)
            ?? container.decode(CloudAIQuotaState.self, forKey: .quota)
    }
}

private struct UsageGenerationsResponse: Decodable {
    let generations: [CloudAIGenerationUsageRecord]
}

private struct PromptConfigResponse: Decodable {
    let promptVersion: String
    let promptHash: String
    let promptBundle: AIPromptBundle?
}
struct FinishRequest: Encodable {
    let generationID: String
    let sessionToken: String
    let validatedCards: Int

    enum CodingKeys: String, CodingKey {
        case generationID = "generationId"
        case sessionToken, validatedCards
    }
}

struct FailRequest: Encodable {
    let generationID: String
    let sessionToken: String

    enum CodingKeys: String, CodingKey {
        case generationID = "generationId"
        case sessionToken
    }
}
private struct EmptyResponse: Decodable { }
private struct ProxyErrorEnvelope: Decodable {
    struct ErrorPayload: Decodable { let message: String? }
    let error: ErrorPayload?
}
