import Foundation
import UIKit

extension AIFlashcardService {
    private static let retryAfterDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter
    }()

    func sendRequest(
        messages: [[String: Any]],
        model: String,
        options: AIGenerationOptions
    ) async throws -> [AIFlashcard] {
        try await performRetriableJSONRequest(messages: messages, model: model) { [self] data in
            let content = try await self.parseResponseContent(from: data)
            return try await self.decodeGeneratedCards(
                from: content,
                contract: options.cardType.outputContract
            )
        }
    }

    func sendDeckTitleRequest(
        messages: [[String: Any]],
        model: String
    ) async throws -> String? {
        return try await performRetriableJSONRequest(messages: messages, model: model) { [self] data in
            let content = try await self.parseResponseContent(from: data)
            let decoded = try JSONDecoder().decode(DeckTitleResponseDTO.self, from: Data(content.utf8))
            return decoded.deck_title?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func performRetriableJSONRequest<T: Sendable>(
        messages: [[String: Any]],
        model: String,
        parser: @escaping @Sendable (Data) async throws -> T
    ) async throws -> T {
        guard let url = apiEndpoint else { throw AIServiceError.networkError }
        let apiKey = try resolvedAPIKey()

        var lastServiceError: AIServiceError?

        for attempt in 0...maxRequestRetryCount {
            try Task.checkCancellation()
            let requestScope = AIDebugTraceContext.currentScope?.with(
                modelName: model,
                operation: AIDebugTraceContext.currentScope?.operation ?? "provider_request",
                attempt: attempt + 1,
                requestID: UUID()
            )

            do {
                return try await withTraceScope(requestScope) { [self] in
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    self.applyStandardHeaders(to: &request, apiKey: apiKey)

                    let body = self.requestBody(messages: messages, model: model)
                    let traceBody = self.traceJSONString(forJSONObject: body) ?? "Failed to pretty-print request body."
                    await self.trace(
                        .requestPrepared,
                        "Prepared provider request.",
                        metadata: [
                            "url": url.absoluteString,
                            "model": model,
                            "message_count": String(messages.count),
                            "request_style": self.provider.requestStyle.title
                        ],
                        payload: traceBody
                    )

                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (data, response) = try await self.session.data(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        await self.trace(
                            .decodeFailed,
                            "Provider response was not an HTTPURLResponse.",
                            metadata: ["model": model]
                        )
                        throw AIServiceError.invalidResponse
                    }

                    await self.trace(
                        .responseReceived,
                        "Received provider response.",
                        metadata: [
                            "status_code": String(http.statusCode),
                            "model": model
                        ],
                        payload: String(decoding: data, as: UTF8.self)
                    )

                    guard (200...299).contains(http.statusCode) else {
                        throw self.httpError(from: http, data: data)
                    }

                    return try await parser(data)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as RetriableRequestError {
                lastServiceError = error.serviceError
                await debugTraceStore.record(
                    stage: .retryScheduled,
                    message: "Retrying provider request after retriable error.",
                    scope: requestScope,
                    metadata: [
                        "service_error": String(describing: error.serviceError),
                        "retry_after": error.retryAfter.map { String($0) } ?? "none"
                    ]
                )
                guard attempt < maxRequestRetryCount else {
                    throw error.serviceError
                }
                try await sleepBeforeRetry(attempt: attempt, retryAfter: error.retryAfter)
            } catch let error as AIServiceError {
                lastServiceError = error
                await debugTraceStore.record(
                    stage: .retryScheduled,
                    message: "Provider request failed with AIServiceError.",
                    scope: requestScope,
                    metadata: [
                        "service_error": String(describing: error),
                        "will_retry": String(attempt < maxRequestRetryCount && shouldRetry(error))
                    ]
                )
                guard attempt < maxRequestRetryCount, shouldRetry(error) else {
                    throw error
                }
                try await sleepBeforeRetry(attempt: attempt, retryAfter: nil)
            } catch let error as URLError {
                let serviceError = mapURLSessionError(error)
                lastServiceError = serviceError
                await debugTraceStore.record(
                    stage: .retryScheduled,
                    message: "Provider request failed with URLSession error.",
                    scope: requestScope,
                    metadata: [
                        "url_error": error.localizedDescription,
                        "mapped_service_error": String(describing: serviceError),
                        "will_retry": String(attempt < maxRequestRetryCount && shouldRetry(serviceError))
                    ]
                )
                guard attempt < maxRequestRetryCount, shouldRetry(serviceError) else {
                    throw serviceError
                }
                try await sleepBeforeRetry(attempt: attempt, retryAfter: nil)
            } catch {
                lastServiceError = .networkError
                await debugTraceStore.record(
                    stage: .retryScheduled,
                    message: "Provider request failed with unexpected error.",
                    scope: requestScope,
                    metadata: [
                        "error": String(describing: error),
                        "will_retry": String(attempt < maxRequestRetryCount)
                    ]
                )
                guard attempt < maxRequestRetryCount else {
                    throw AIServiceError.networkError
                }
                try await sleepBeforeRetry(attempt: attempt, retryAfter: nil)
            }
        }

        throw lastServiceError ?? .networkError
    }

    func resolvedAPIKey() throws -> String {
        let trimmedAPIKey = provider.trimmedAPIKey
        guard !trimmedAPIKey.isEmpty else { throw AIServiceError.invalidAPIKey }
        return trimmedAPIKey
    }

    func applyStandardHeaders(to request: inout URLRequest, apiKey: String) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let referer = provider.httpRefererURL?.absoluteString, !referer.isEmpty {
            request.setValue(referer, forHTTPHeaderField: "HTTP-Referer")
        }

        let title = provider.trimmedXTitle
        if !title.isEmpty {
            request.setValue(title, forHTTPHeaderField: "X-Title")
        }
    }

    func requestBody(messages: [[String: Any]], model: String) -> [String: Any] {
        switch provider.requestStyle {
        case .openAICompatible:
            var body: [String: Any] = [
                "model": model,
                "messages": messages,
                "response_format": ["type": "json_object"]
            ]

            if supportsTemperatureParameter(for: model) {
                body["temperature"] = 0.2
            }

            if let extraBody = provider.extraBodyObject {
                body.merge(extraBody) { _, new in new }
            }

            return body
        }
    }

    func traceJSONString(forJSONObject object: Any) -> String? {
        let sanitizedObject = sanitizedTraceJSONObject(object)
        guard JSONSerialization.isValidJSONObject(sanitizedObject),
              let data = try? JSONSerialization.data(withJSONObject: sanitizedObject, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return string
    }

    func sanitizedTraceJSONObject(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.mapValues { sanitizedTraceJSONObject($0) }
        }

        if let array = value as? [Any] {
            return array.map { sanitizedTraceJSONObject($0) }
        }

        if let string = value as? String {
            if string.hasPrefix("data:image"),
               let separatorRange = string.range(of: "base64,") {
                let prefix = String(string[..<separatorRange.upperBound])
                let encodedContent = String(string[separatorRange.upperBound...])
                return "\(prefix)<redacted \(encodedContent.count) chars>"
            }
            return string
        }

        return value
    }

    func shouldRetry(_ error: AIServiceError) -> Bool {
        switch error {
        case .networkError, .invalidResponse, .parsingFailed, .rateLimitExceeded, .timeout:
            return true
        case .invalidAPIKey:
            return false
        case .unknown(let message):
            if message.contains("HTTP 408") || message.contains("HTTP 409") || message.contains("HTTP 425") ||
                message.contains("HTTP 429") || message.contains("HTTP 500") || message.contains("HTTP 502") ||
                message.contains("HTTP 503") || message.contains("HTTP 504") {
                return true
            }
            return false
        }
    }

    func shouldAttemptPlanSplit(after error: Error) -> Bool {
        if let retriable = error as? RetriableRequestError {
            return shouldRetry(retriable.serviceError)
        }

        if let serviceError = error as? AIServiceError {
            return shouldRetry(serviceError)
        }

        if error is URLError {
            return true
        }

        return false
    }

    func mapURLSessionError(_ error: URLError) -> AIServiceError {
        switch error.code {
        case .timedOut:
            return .timeout
        case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed, .notConnectedToInternet, .internationalRoamingOff, .callIsActive, .dataNotAllowed:
            return .networkError
        default:
            return .networkError
        }
    }

    func httpError(from response: HTTPURLResponse, data: Data) -> Error {
        let message = apiErrorMessage(from: data, statusCode: response.statusCode)
        let retryAfter = retryAfterInterval(from: response)

        switch response.statusCode {
        case 401, 403:
            return AIServiceError.invalidAPIKey
        case 408:
            return RetriableRequestError(serviceError: .timeout, retryAfter: retryAfter)
        case 429:
            return RetriableRequestError(serviceError: .rateLimitExceeded, retryAfter: retryAfter)
        case 500, 502, 503, 504:
            return RetriableRequestError(serviceError: .unknown(message), retryAfter: retryAfter)
        default:
            return AIServiceError.unknown(message)
        }
    }

    func retryAfterInterval(from response: HTTPURLResponse) -> TimeInterval? {
        guard let rawValue = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }

        if let seconds = TimeInterval(rawValue), seconds > 0 {
            return seconds
        }

        guard let date = Self.retryAfterDateFormatter.date(from: rawValue) else {
            return nil
        }

        return max(date.timeIntervalSinceNow, 0)
    }

    func sleepBeforeRetry(attempt: Int, retryAfter: TimeInterval?) async throws {
        let delayNanoseconds: UInt64

        if let retryAfter, retryAfter > 0 {
            delayNanoseconds = UInt64(retryAfter * 1_000_000_000)
        } else {
            let exponentialMultiplier = pow(2.0, Double(attempt))
            let exponentialDelay = UInt64(Double(baseRetryDelayNanoseconds) * exponentialMultiplier)
            let jitter = UInt64.random(in: 0...400_000_000)
            delayNanoseconds = min(exponentialDelay + jitter, maxRetryDelayNanoseconds)
        }

        try await Task.sleep(nanoseconds: delayNanoseconds)
    }

    func withExecutionTimeout<T: Sendable>(
        nanoseconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: nanoseconds)
                throw RetriableRequestError(serviceError: .timeout, retryAfter: nil)
            }

            defer { group.cancelAll() }

            guard let result = try await group.next() else {
                throw AIServiceError.timeout
            }

            return result
        }
    }

    func batchFailureDescription<Plan: RecoverableBatchPlan>(for plan: Plan, error: Error) -> String {
        let baseDescription: String

        if let serviceError = error as? AIServiceError {
            baseDescription = serviceError.localizedDescription
        } else if let retriable = error as? RetriableRequestError {
            baseDescription = retriable.serviceError.localizedDescription
        } else if let urlError = error as? URLError {
            baseDescription = mapURLSessionError(urlError).localizedDescription
        } else {
            baseDescription = error.localizedDescription
        }

        return "• \(plan.sourceLabel) — \(plan.targetCards) cards: \(baseDescription)"
    }

    // -------------------------------------------------------------------------
}
