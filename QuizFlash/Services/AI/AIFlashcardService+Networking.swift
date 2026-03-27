import Foundation
import UIKit
import SwiftData

extension AIFlashcardService {
    func sendRequest(
        messages: [[String: Any]],
        model: String,
        options: AIGenerationOptions
    ) async throws -> [AIFlashcard] {
        try await performRetriableJSONRequest(messages: messages, model: model) { [self] data in
            let content = try self.parseResponseContent(from: data)
            return try self.decodeGeneratedCards(
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
            let content = try self.parseResponseContent(from: data)
            let decoded = try JSONDecoder().decode(DeckTitleResponseDTO.self, from: Data(content.utf8))
            return decoded.deck_title?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func sendConversionRequest(
        messages: [[String: Any]],
        model: String,
        sourceCards: [AICardConversionSource],
        targetType: AICardGenerationType
    ) async throws -> [AICardConversionOutput] {
        try await performRetriableJSONRequest(messages: messages, model: model) { [self] data in
            let content = try self.parseResponseContent(from: data)
            return try self.decodeConvertedCards(
                from: content,
                sourceCards: sourceCards,
                contract: targetType.outputContract
            )
        }
    }

    func sendQualityFirstMatchGenerationRequest(
        targetCards: Int,
        model: String,
        options: AIGenerationOptions,
        messageBuilder: (_ targetCards: Int, _ retryHints: [String]) -> [[String: Any]]
    ) async throws -> MatchGenerationQualityResult {
        guard targetCards > 0 else {
            return MatchGenerationQualityResult(cards: [], shortfallCount: 0)
        }

        var acceptedCards: [AIFlashcard] = []
        var acceptedHints: Set<String> = []
        var retryHints: [String] = []
        var remainingCards = targetCards

        for attempt in 0..<maxMatchQualityAttempts where remainingCards > 0 {
            var messages = messageBuilder(remainingCards, retryHints)
            if attempt > 0 {
                messages = appendingMatchQualityRetryInstruction(
                    to: messages,
                    targetCount: remainingCards,
                    retryHints: retryHints
                )
            }

            let cards = try await sendRequest(
                messages: messages,
                model: model,
                options: options
            )

            for card in cards {
                let retryHint = matchQualityRetryHint(from: card)

                if let acceptedCard = acceptedMatchCard(from: card),
                   acceptedCards.count < targetCards,
                   acceptedHints.insert(retryHint).inserted {
                    acceptedCards.append(acceptedCard)
                } else {
                    retryHints.append(retryHint)
                }
            }

            retryHints = Array(Set(retryHints)).sorted()
            remainingCards = max(0, targetCards - acceptedCards.count)
        }

        return MatchGenerationQualityResult(
            cards: acceptedCards,
            shortfallCount: max(0, targetCards - acceptedCards.count)
        )
    }

    func sendQualityFirstMatchConversionRequest(
        sourceCards: [AICardConversionSource],
        level: AICardGenerationLevel
    ) async throws -> MatchConversionQualityResult {
        guard !sourceCards.isEmpty else {
            return MatchConversionQualityResult(outputs: [], shortfallCount: 0)
        }

        var acceptedOutputs: [AICardConversionOutput] = []
        var pendingSources = sourceCards
        var retryHints: [String] = []

        for attempt in 0..<maxMatchQualityAttempts where !pendingSources.isEmpty {
            var messages = buildConversionMessages(
                sourceCards: pendingSources,
                targetType: .match,
                level: level
            )
            if attempt > 0 {
                messages = appendingMatchQualityRetryInstruction(
                    to: messages,
                    targetCount: pendingSources.count,
                    retryHints: retryHints
                )
            }

            let outputs = try await sendConversionRequest(
                messages: messages,
                model: textModel,
                sourceCards: pendingSources,
                targetType: .match
            )

            let filterResult = filterAcceptedMatchConversionOutputs(outputs)
            acceptedOutputs.append(contentsOf: filterResult.outputs)
            retryHints.append(contentsOf: filterResult.retryHints)
            retryHints = Array(Set(retryHints)).sorted()
            pendingSources = pendingSources.filter { filterResult.rejectedSourceIDs.contains($0.id) }
        }

        return MatchConversionQualityResult(
            outputs: acceptedOutputs,
            shortfallCount: pendingSources.count
        )
    }

    func sendQualityFirstWriteConversionRequest(
        sourceCards: [AICardConversionSource],
        level: AICardGenerationLevel
    ) async throws -> WriteConversionQualityResult {
        guard !sourceCards.isEmpty else {
            return WriteConversionQualityResult(outputs: [], shortfallCount: 0)
        }

        var acceptedOutputs: [AICardConversionOutput] = []
        var pendingSources = sourceCards
        var retryHints: [String] = []

        for attempt in 0..<maxMatchQualityAttempts where !pendingSources.isEmpty {
            var messages = buildConversionMessages(
                sourceCards: pendingSources,
                targetType: .write,
                level: level
            )
            if attempt > 0 {
                messages = appendingWriteQualityRetryInstruction(
                    to: messages,
                    targetCount: pendingSources.count,
                    retryHints: retryHints
                )
            }

            let outputs = try await sendConversionRequest(
                messages: messages,
                model: textModel,
                sourceCards: pendingSources,
                targetType: .write
            )

            let filterResult = filterAcceptedWriteConversionOutputs(outputs)
            acceptedOutputs.append(contentsOf: filterResult.outputs)
            retryHints.append(contentsOf: filterResult.retryHints)
            retryHints = Array(Set(retryHints)).sorted()
            pendingSources = pendingSources.filter { filterResult.rejectedSourceIDs.contains($0.id) }
        }

        return WriteConversionQualityResult(
            outputs: acceptedOutputs,
            shortfallCount: pendingSources.count
        )
    }

    func filterAcceptedMatchConversionOutputs(
        _ outputs: [AICardConversionOutput]
    ) -> MatchConversionFilterResult {
        var acceptedOutputs: [AICardConversionOutput] = []
        var rejectedSourceIDs: Set<PersistentIdentifier> = []
        var retryHints: [String] = []

        for output in outputs {
            if let acceptedCard = acceptedMatchCard(from: output.generatedCard) {
                acceptedOutputs.append(
                    AICardConversionOutput(
                        sourceCardID: output.sourceCardID,
                        generatedCard: acceptedCard
                    )
                )
            } else {
                rejectedSourceIDs.insert(output.sourceCardID)
                retryHints.append(matchQualityRetryHint(from: output.generatedCard))
            }
        }

        return MatchConversionFilterResult(
            outputs: acceptedOutputs,
            rejectedSourceIDs: rejectedSourceIDs,
            retryHints: Array(Set(retryHints)).sorted()
        )
    }

    func filterAcceptedWriteConversionOutputs(
        _ outputs: [AICardConversionOutput]
    ) -> WriteConversionFilterResult {
        var acceptedOutputs: [AICardConversionOutput] = []
        var rejectedSourceIDs: Set<PersistentIdentifier> = []
        var retryHints: [String] = []

        for output in outputs {
            if let acceptedCard = acceptedWriteCard(from: output.generatedCard) {
                acceptedOutputs.append(
                    AICardConversionOutput(
                        sourceCardID: output.sourceCardID,
                        generatedCard: acceptedCard
                    )
                )
            } else {
                rejectedSourceIDs.insert(output.sourceCardID)
                retryHints.append(writeQualityRetryHint(from: output.generatedCard))
            }
        }

        return WriteConversionFilterResult(
            outputs: acceptedOutputs,
            rejectedSourceIDs: rejectedSourceIDs,
            retryHints: Array(Set(retryHints)).sorted()
        )
    }

    func acceptedMatchCard(from card: AIFlashcard) -> AIFlashcard? {
        guard case .match(let content) = card.content else { return nil }

        let evaluation = MatchCardQualityPolicy.evaluate(
            prompt: content.prompt,
            answer: content.answer
        )
        guard evaluation.isCompact else { return nil }

        return AIFlashcard(
            id: card.id,
            content: .match(
                AIMatchCardContent(
                    prompt: evaluation.prompt,
                    answer: evaluation.answer
                )
            )
        )
    }

    func matchQualityRetryHint(from card: AIFlashcard) -> String {
        guard case .match(let content) = card.content else {
            return card.promptHint
        }

        return MatchCardQualityPolicy.evaluate(
            prompt: content.prompt,
            answer: content.answer
        ).retryHint
    }

    func acceptedWriteCard(from card: AIFlashcard) -> AIFlashcard? {
        guard case .write(let content) = card.content else { return nil }

        let sourceText = content.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let omittedText = content.omittedText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sourceText.isEmpty, !omittedText.isEmpty else { return nil }
        guard anchoredWriteOmissionCount(sourceText: sourceText, omittedText: omittedText) == 1 else {
            return nil
        }

        return AIFlashcard(
            id: card.id,
            content: .write(
                AIWriteCardContent(
                    sourceText: sourceText,
                    omittedText: omittedText
                )
            )
        )
    }

    func writeQualityRetryHint(from card: AIFlashcard) -> String {
        guard case .write(let content) = card.content else {
            return card.promptHint
        }

        let sourcePreview = String(content.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(72))
        let omittedPreview = content.omittedText.trimmingCharacters(in: .whitespacesAndNewlines)

        if omittedPreview.isEmpty {
            return "The omitted_text field was empty."
        }

        let occurrenceCount = anchoredWriteOmissionCount(
            sourceText: content.sourceText,
            omittedText: omittedPreview
        )

        if occurrenceCount == 0 {
            return "The omitted text \"\(omittedPreview)\" was not present verbatim inside source_text. Source preview: \(sourcePreview)"
        }

        return "The omitted text \"\(omittedPreview)\" appeared \(occurrenceCount)x in source_text. It must appear exactly once."
    }

    func appendingMatchQualityRetryInstruction(
        to messages: [[String: Any]],
        targetCount: Int,
        retryHints: [String]
    ) -> [[String: Any]] {
        let rejectedPreview = retryHints
            .prefix(6)
            .map { "- \($0)" }
            .joined(separator: "\n")

        let retryInstruction = """
        The previous Match attempt produced prompt-answer pairs that were too verbose for fast matching rounds.
        Regenerate EXACTLY \(targetCount) new Match cards that are tighter and more scannable.
        Prefer term -> definition, notation -> meaning, structure -> property, or cue -> direct counterpart.
        Avoid repeating or paraphrasing these rejected weak pairs:
        \(rejectedPreview.isEmpty ? "- No rejected pairs listed." : rejectedPreview)
        """

        var updatedMessages = messages
        updatedMessages.append([
            "role": "user",
            "content": retryInstruction
        ])
        return updatedMessages
    }

    func appendingWriteQualityRetryInstruction(
        to messages: [[String: Any]],
        targetCount: Int,
        retryHints: [String]
    ) -> [[String: Any]] {
        let rejectedPreview = retryHints
            .prefix(6)
            .map { "- \($0)" }
            .joined(separator: "\n")

        let retryInstruction = """
        The previous Write attempt produced cards whose omitted_text was not anchored correctly.
        Regenerate EXACTLY \(targetCount) new Write cards.
        CRITICAL:
        - omitted_text MUST appear inside source_text as an exact verbatim substring
        - omitted_text MUST appear exactly once
        - keep the blank compact and directly typeable
        Avoid repeating these rejected patterns:
        \(rejectedPreview.isEmpty ? "- No rejected patterns listed." : rejectedPreview)
        """

        var updatedMessages = messages
        updatedMessages.append([
            "role": "user",
            "content": retryInstruction
        ])
        return updatedMessages
    }

    func anchoredWriteOmissionCount(sourceText: String, omittedText: String) -> Int {
        let trimmedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOmitted = omittedText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedSource.isEmpty, !trimmedOmitted.isEmpty else { return 0 }

        let nsSource = trimmedSource as NSString
        var searchRange = NSRange(location: 0, length: nsSource.length)
        var count = 0

        while searchRange.length > 0 {
            let foundRange = nsSource.range(of: trimmedOmitted, options: [], range: searchRange)
            guard foundRange.location != NSNotFound, foundRange.length > 0 else { break }

            count += 1
            let nextLocation = foundRange.location + foundRange.length
            guard nextLocation < nsSource.length else { break }
            searchRange = NSRange(location: nextLocation, length: nsSource.length - nextLocation)
        }

        return count
    }

    func performRetriableJSONRequest<T>(
        messages: [[String: Any]],
        model: String,
        parser: @escaping (Data) throws -> T
    ) async throws -> T {
        guard let url = apiEndpoint else { throw AIServiceError.networkError }
        let apiKey = try resolvedAPIKey()

        var lastServiceError: AIServiceError?

        for attempt in 0...maxRequestRetryCount {
            try Task.checkCancellation()

            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                applyStandardHeaders(to: &request, apiKey: apiKey)

                let body = requestBody(messages: messages, model: model)
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw AIServiceError.invalidResponse
                }
                guard (200...299).contains(http.statusCode) else {
                    throw httpError(from: http, data: data)
                }

                return try parser(data)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as RetriableRequestError {
                lastServiceError = error.serviceError
                guard attempt < maxRequestRetryCount else {
                    throw error.serviceError
                }
                try await sleepBeforeRetry(attempt: attempt, retryAfter: error.retryAfter)
            } catch let error as AIServiceError {
                lastServiceError = error
                guard attempt < maxRequestRetryCount, shouldRetry(error) else {
                    throw error
                }
                try await sleepBeforeRetry(attempt: attempt, retryAfter: nil)
            } catch let error as URLError {
                let serviceError = mapURLSessionError(error)
                lastServiceError = serviceError
                guard attempt < maxRequestRetryCount, shouldRetry(serviceError) else {
                    throw serviceError
                }
                try await sleepBeforeRetry(attempt: attempt, retryAfter: nil)
            } catch {
                lastServiceError = .networkError
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

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"

        guard let date = formatter.date(from: rawValue) else {
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

