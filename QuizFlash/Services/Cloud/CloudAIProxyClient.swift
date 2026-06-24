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
}

@MainActor
final class CloudAIProxyClient {
    static let shared = CloudAIProxyClient()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func prefetchPromptBundle() async {
        _ = try? await currentPromptBundle()
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
        return CloudAIGenerationSession(
            baseURL: baseURL,
            generationID: response.generationID,
            sessionToken: response.sessionToken,
            uid: user.uid,
            targetCards: response.targetCards,
            quota: response.quota,
            promptBundle: promptBundle,
            promptCacheStatus: promptCacheStatus
        )
    }

    func finishGeneration(_ generation: CloudAIGenerationSession, validatedCards: Int) async throws -> CloudAIQuotaState {
        try await sendJSON(
            endpoint: generation.baseURL.appending(path: "v1/generations/finish"),
            method: "POST",
            headers: ["X-QuizFlash-UID": generation.uid],
            body: FinishRequest(generationID: generation.generationID, sessionToken: generation.sessionToken, validatedCards: validatedCards)
        )
    }

    func failGeneration(_ generation: CloudAIGenerationSession) async {
        let _: EmptyResponse? = try? await sendJSON(
            endpoint: generation.baseURL.appending(path: "v1/generations/fail"),
            method: "POST",
            headers: ["X-QuizFlash-UID": generation.uid],
            body: FailRequest(generationID: generation.generationID, sessionToken: generation.sessionToken)
        )
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

private struct StartResponse: Decodable {
    let generationID: String
    let sessionToken: String
    let targetCards: Int
    let quota: CloudAIQuotaState
    let promptVersion: String
    let promptHash: String
    let promptBundle: AIPromptBundle?
}
private struct PromptConfigResponse: Decodable {
    let promptVersion: String
    let promptHash: String
    let promptBundle: AIPromptBundle?
}
private struct FinishRequest: Encodable { let generationID: String; let sessionToken: String; let validatedCards: Int }
private struct FailRequest: Encodable { let generationID: String; let sessionToken: String }
private struct EmptyResponse: Decodable { }
private struct ProxyErrorEnvelope: Decodable {
    struct ErrorPayload: Decodable { let message: String? }
    let error: ErrorPayload?
}
