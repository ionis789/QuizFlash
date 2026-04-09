import Foundation
import UIKit
import SwiftData

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

    func sendConversionRequest(
        messages: [[String: Any]],
        model: String,
        sourceCards: [AICardConversionSource],
        targetType: AICardGenerationType
    ) async throws -> [AICardConversionOutput] {
        try await performRetriableJSONRequest(messages: messages, model: model) { [self] data in
            let content = try await self.parseResponseContent(from: data)
            return try await self.decodeConvertedCards(
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
        existingPairKeys: Set<String> = [],
        messageBuilder: (_ targetCards: Int, _ retryHints: [String]) -> [[String: Any]]
    ) async throws -> MatchGenerationQualityResult {
        guard targetCards > 0 else {
            return MatchGenerationQualityResult(
                cards: [],
                shortfallCount: 0,
                diagnostics: MatchAIBatchDiagnostics()
            )
        }

        var acceptedCards: [AIFlashcard] = []
        var acceptedPairKeys: Set<String> = existingPairKeys
        var retryHints: [String] = []
        var remainingCards = targetCards
        var diagnostics = MatchAIBatchDiagnostics()

        for attempt in 0..<maxMatchQualityAttempts where remainingCards > 0 {
            var messages = messageBuilder(remainingCards, retryHints)
            if attempt > 0 {
                messages = appendingMatchQualityRetryInstruction(
                    to: messages,
                    targetCount: remainingCards,
                    retryHints: retryHints
                )
            }

            await trace(
                .requestPrepared,
                "Prepared Match generation quality attempt.",
                metadata: [
                    "quality_attempt": String(attempt + 1),
                    "remaining_target_cards": String(remainingCards),
                    "retry_hint_count": String(retryHints.count)
                ]
            )

            let cards = try await sendRequest(
                messages: messages,
                model: model,
                options: options
            )

            var attemptDiagnostics = MatchAIBatchDiagnostics()
            attemptDiagnostics.increment(
                .providerUnderfilled,
                by: max(0, remainingCards - cards.count)
            )
            var attemptAcceptedCards: [AIFlashcard] = []
            var attemptRetryHints: [String] = []
            var feedbackLines: [String] = []

            for card in cards {
                guard let inspectedCard = inspectMatchCard(card) else {
                    attemptDiagnostics.increment(.structurallyRejected)
                    attemptRetryHints.append(matchQualityRetryHint(from: card))
                    continue
                }

                let pairKey = matchPairKey(
                    prompt: inspectedCard.evaluation.prompt,
                    answer: inspectedCard.evaluation.answer
                )
                let retryHint = inspectedCard.evaluation.retryHint

                guard !acceptedPairKeys.contains(pairKey) else {
                    attemptDiagnostics.increment(.duplicatePair)
                    attemptRetryHints.append(retryHint)
                    continue
                }

                if inspectedCard.isLowQuality {
                    attemptDiagnostics.lowQualityAcceptedCount += 1
                }

                guard attemptAcceptedCards.count < targetCards else { continue }
                attemptAcceptedCards.append(inspectedCard.card)
                feedbackLines.append(matchQualityFeedbackLine(for: inspectedCard.evaluation))
            }

            let shouldRetryWeakAttempt = shouldRetryWeakMatchAttempt(
                acceptedCount: attemptAcceptedCards.count,
                lowQualityCount: attemptDiagnostics.lowQualityAcceptedCount,
                attempt: attempt
            )

            if shouldRetryWeakAttempt {
                attemptRetryHints.append(contentsOf: attemptAcceptedCards.compactMap { card in
                    guard let inspectedCard = inspectMatchCard(card) else { return nil }
                    return inspectedCard.evaluation.retryHint
                })
                retryHints = Array(Set(retryHints + attemptRetryHints)).sorted()
                await trace(
                    .retryScheduled,
                    "Retrying Match generation because the batch was semantically weak.",
                    metadata: [
                        "quality_attempt": String(attempt + 1),
                        "accepted_card_count": String(attemptAcceptedCards.count),
                        "low_quality_accepted": String(attemptDiagnostics.lowQualityAcceptedCount)
                    ],
                    payload: feedbackLines.joined(separator: "\n")
                )
                continue
            }

            for acceptedCard in attemptAcceptedCards {
                guard case .match(let content) = acceptedCard.content else { continue }
                acceptedPairKeys.insert(matchPairKey(prompt: content.prompt, answer: content.answer))
            }

            acceptedCards.append(contentsOf: attemptAcceptedCards)
            diagnostics.merge(attemptDiagnostics)
            retryHints = Array(Set(retryHints + attemptRetryHints)).sorted()
            remainingCards = max(0, targetCards - acceptedCards.count)
            await trace(
                .qualityEvaluated,
                "Evaluated Match generation quality attempt.",
                metadata: [
                    "quality_attempt": String(attempt + 1),
                    "provider_card_count": String(cards.count),
                    "accepted_card_count": String(attemptAcceptedCards.count),
                    "remaining_target_cards": String(remainingCards),
                    "low_quality_accepted": String(attemptDiagnostics.lowQualityAcceptedCount)
                ],
                payload: feedbackLines.joined(separator: "\n")
            )
        }

        return MatchGenerationQualityResult(
            cards: acceptedCards,
            shortfallCount: max(0, targetCards - acceptedCards.count),
            diagnostics: diagnostics
        )
    }

    func sendQualityFirstMatchConversionRequest(
        sourceCards: [AICardConversionSource],
        targetCount: Int,
        level: AICardGenerationLevel,
        approvedMatchExamples: [String] = [],
        matchOverlapHints: [String] = [],
        existingPairKeys: Set<String> = []
    ) async throws -> MatchConversionQualityResult {
        guard !sourceCards.isEmpty, targetCount > 0 else {
            return MatchConversionQualityResult(
                outputs: [],
                shortfallCount: 0,
                diagnostics: MatchAIBatchDiagnostics()
            )
        }

        var acceptedOutputs: [AICardConversionOutput] = []
        var pendingSources = sourceCards
        var retryHints: [String] = []
        var acceptedPairKeys: Set<String> = existingPairKeys
        var diagnostics = MatchAIBatchDiagnostics()

        for attempt in 0..<maxMatchQualityAttempts where !pendingSources.isEmpty {
            let remainingTargetCount = max(0, targetCount - acceptedOutputs.count)
            guard remainingTargetCount > 0 else { break }

            var messages = buildConversionMessages(
                sourceCards: pendingSources,
                targetType: .match,
                level: level,
                targetCount: remainingTargetCount,
                approvedMatchExamples: approvedMatchExamples,
                matchOverlapHints: matchOverlapHints
            )
            if attempt > 0 {
                messages = appendingMatchQualityRetryInstruction(
                    to: messages,
                    targetCount: remainingTargetCount,
                    retryHints: retryHints
                )
            }

            await trace(
                .requestPrepared,
                "Prepared Match conversion quality attempt.",
                metadata: [
                    "quality_attempt": String(attempt + 1),
                    "pending_source_count": String(pendingSources.count),
                    "remaining_target_cards": String(remainingTargetCount),
                    "retry_hint_count": String(retryHints.count)
                ]
            )

            let outputs = try await sendConversionRequest(
                messages: messages,
                model: textModel,
                sourceCards: pendingSources,
                targetType: .match
            )

            diagnostics.increment(
                .providerUnderfilled,
                by: max(0, remainingTargetCount - outputs.count)
            )

            let filterResult = filterAcceptedMatchConversionOutputs(
                outputs,
                existingPairKeys: acceptedPairKeys
            )

            let shouldRetryWeakAttempt = shouldRetryWeakMatchAttempt(
                acceptedCount: filterResult.outputs.count,
                lowQualityCount: filterResult.diagnostics.lowQualityAcceptedCount,
                attempt: attempt
            )

            if shouldRetryWeakAttempt {
                retryHints = Array(Set(retryHints + filterResult.retryHints)).sorted()
                await trace(
                    .retryScheduled,
                    "Retrying Match conversion because the candidate slice was semantically weak.",
                    metadata: [
                        "quality_attempt": String(attempt + 1),
                        "accepted_output_count": String(filterResult.outputs.count),
                        "low_quality_accepted": String(filterResult.diagnostics.lowQualityAcceptedCount)
                    ],
                    payload: filterResult.feedbackLines.joined(separator: "\n")
                )
                continue
            }

            acceptedOutputs.append(contentsOf: filterResult.outputs)
            acceptedPairKeys.formUnion(
                filterResult.outputs.compactMap { output in
                    guard case .match(let content) = output.generatedCard.content else { return nil }
                    return matchPairKey(prompt: content.prompt, answer: content.answer)
                }
            )
            retryHints = Array(Set(retryHints + filterResult.retryHints)).sorted()
            diagnostics.merge(filterResult.diagnostics)
            pendingSources = pendingSources.filter { filterResult.rejectedSourceIDs.contains($0.id) }
            await trace(
                .qualityEvaluated,
                "Evaluated Match conversion quality attempt.",
                metadata: [
                    "quality_attempt": String(attempt + 1),
                    "provider_output_count": String(outputs.count),
                    "accepted_output_count": String(filterResult.outputs.count),
                    "rejected_source_count": String(filterResult.rejectedSourceIDs.count),
                    "remaining_pending_sources": String(pendingSources.count),
                    "low_quality_accepted": String(filterResult.diagnostics.lowQualityAcceptedCount)
                ],
                payload: filterResult.feedbackLines.joined(separator: "\n")
            )
        }

        return MatchConversionQualityResult(
            outputs: acceptedOutputs,
            shortfallCount: max(0, targetCount - acceptedOutputs.count),
            diagnostics: diagnostics
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
        _ outputs: [AICardConversionOutput],
        existingPairKeys: Set<String> = []
    ) -> MatchConversionFilterResult {
        var acceptedOutputs: [AICardConversionOutput] = []
        var rejectedSourceIDs: Set<PersistentIdentifier> = []
        var retryHints: [String] = []
        var seenPairKeys = existingPairKeys
        var seenSourceIDs: Set<PersistentIdentifier> = []
        var diagnostics = MatchAIBatchDiagnostics()
        var feedbackLines: [String] = []

        for output in outputs {
            guard seenSourceIDs.insert(output.sourceCardID).inserted else {
                rejectedSourceIDs.insert(output.sourceCardID)
                diagnostics.increment(.invalidSourceMapping)
                retryHints.append(matchQualityRetryHint(from: output.generatedCard))
                continue
            }

            guard let inspectedCard = inspectMatchCard(output.generatedCard) else {
                rejectedSourceIDs.insert(output.sourceCardID)
                retryHints.append(matchQualityRetryHint(from: output.generatedCard))
                diagnostics.increment(.structurallyRejected)
                continue
            }

            let pairKey = matchPairKey(
                prompt: inspectedCard.evaluation.prompt,
                answer: inspectedCard.evaluation.answer
            )
            guard seenPairKeys.insert(pairKey).inserted else {
                rejectedSourceIDs.insert(output.sourceCardID)
                retryHints.append(inspectedCard.evaluation.retryHint)
                diagnostics.increment(.duplicatePair)
                continue
            }

            if inspectedCard.isLowQuality {
                diagnostics.lowQualityAcceptedCount += 1
            }
            feedbackLines.append(matchQualityFeedbackLine(for: inspectedCard.evaluation))

            acceptedOutputs.append(
                AICardConversionOutput(
                    sourceCardID: output.sourceCardID,
                    generatedCard: inspectedCard.card
                )
            )
        }

        let result = MatchConversionFilterResult(
            outputs: acceptedOutputs,
            rejectedSourceIDs: rejectedSourceIDs,
            retryHints: Array(Set(retryHints)).sorted(),
            diagnostics: diagnostics,
            feedbackLines: feedbackLines
        )
        Task {
            await self.trace(
                .qualityEvaluated,
                "Filtered Match conversion outputs.",
                metadata: [
                    "accepted_output_count": String(result.outputs.count),
                    "rejected_source_count": String(result.rejectedSourceIDs.count),
                    "retry_hint_count": String(result.retryHints.count),
                    "low_quality_accepted": String(result.diagnostics.lowQualityAcceptedCount)
                ],
                payload: result.feedbackLines.joined(separator: "\n")
            )
        }
        return result
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
        inspectMatchCard(card)?.card
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

    func inspectMatchCard(
        _ card: AIFlashcard
    ) -> (
        card: AIFlashcard,
        evaluation: MatchCardQualityEvaluation,
        isLowQuality: Bool
    )? {
        guard case .match(let content) = card.content else { return nil }

        let evaluation = MatchCardQualityPolicy.evaluate(
            prompt: content.prompt,
            answer: content.answer
        )
        guard !evaluation.prompt.isEmpty, !evaluation.answer.isEmpty else { return nil }

        return (
            AIFlashcard(
                id: card.id,
                content: .match(
                    AIMatchCardContent(
                        prompt: evaluation.prompt,
                        answer: evaluation.answer
                    )
                )
            ),
            evaluation,
            !evaluation.isStrongExample
        )
    }

    func matchPairKey(prompt: String, answer: String) -> String {
        "\(prompt.lowercased())\u{1F}|\u{1F}\(answer.lowercased())"
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
        The previous Match attempt was semantically weak for match gameplay.
        Regenerate UP TO \(targetCount) stronger Match cards.
        PRIORITIES:
        - use one stable relation family
        - prefer atomic concept labels, motifs, roles, notations, or rule names as prompts
        - answers must be the direct counterpart only
        - avoid question-style prompts
        - avoid list-like or explanatory answers
        - if a source idea is broad, choose a tighter sub-concept instead of summarizing the whole paragraph
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

    func shouldRetryWeakMatchAttempt(
        acceptedCount: Int,
        lowQualityCount: Int,
        attempt: Int
    ) -> Bool {
        guard attempt < maxMatchQualityAttempts - 1 else { return false }
        guard acceptedCount >= 2 else { return false }
        return lowQualityCount == acceptedCount
    }

    func matchQualityFeedbackLine(
        for evaluation: MatchCardQualityEvaluation
    ) -> String {
        let issueSuffix = evaluation.qualityIssues.isEmpty
            ? "strong"
            : "issues: \(evaluation.qualityIssues.joined(separator: ", "))"
        return "\"\(evaluation.prompt)\" -> \"\(evaluation.answer)\" [\(issueSuffix)]"
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
