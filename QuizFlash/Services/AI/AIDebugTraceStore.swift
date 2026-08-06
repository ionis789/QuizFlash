//
//  AIDebugTraceStore.swift
//  QuizFlash
//
//  Structured tracing for AI generation runs.
//

import Foundation
import OSLog

nonisolated enum AIDebugTracePreferenceKeys {
    static let debugTracingEnabled = "preferences.ai.debugTracingEnabled"
}

nonisolated enum AIDebugRunKind: String, Codable, Sendable {
    case generation
    case utility
}

nonisolated enum AIDebugTraceStage: String, Codable, Sendable {
    case runStarted
    case planPrepared
    case blueprintDirect
    case blueprintMap
    case blueprintReduce
    case blueprintValidated
    case blueprintValidationFailed
    case blueprintRepair
    case blueprintPlanPrepared
    case batchStarted
    case batchCompleted
    case batchRecovered
    case requestPrepared
    case responseReceived
    case responseContentExtracted
    case decodePrepared
    case decodeSucceeded
    case decodeFailed
    case qualityEvaluated
    case retryScheduled
    case runCompleted
    case runFailed
}

nonisolated struct AIDebugTraceRunDescriptor: Sendable {
    let kind: AIDebugRunKind
    let targetType: String
    let sourceKind: String
    let targetCount: Int?
    let sourceCount: Int?
    let providerName: String
    let modelName: String?
    let metadata: [String: String]
}

nonisolated struct AIDebugTraceScope: Sendable {
    let runID: UUID
    let kind: AIDebugRunKind
    let targetType: String
    let sourceKind: String
    let providerName: String
    let modelName: String?
    let operation: String?
    let batchIndex: Int?
    let totalBatches: Int?
    let sourceLabel: String?
    let plannedCardCount: Int?
    let attempt: Int?
    let requestID: UUID?

    init(
        runID: UUID,
        kind: AIDebugRunKind,
        targetType: String,
        sourceKind: String,
        providerName: String,
        modelName: String? = nil,
        operation: String? = nil,
        batchIndex: Int? = nil,
        totalBatches: Int? = nil,
        sourceLabel: String? = nil,
        plannedCardCount: Int? = nil,
        attempt: Int? = nil,
        requestID: UUID? = nil
    ) {
        self.runID = runID
        self.kind = kind
        self.targetType = targetType
        self.sourceKind = sourceKind
        self.providerName = providerName
        self.modelName = modelName
        self.operation = operation
        self.batchIndex = batchIndex
        self.totalBatches = totalBatches
        self.sourceLabel = sourceLabel
        self.plannedCardCount = plannedCardCount
        self.attempt = attempt
        self.requestID = requestID
    }

    func with(
        modelName: String? = nil,
        operation: String? = nil,
        batchIndex: Int? = nil,
        totalBatches: Int? = nil,
        sourceLabel: String? = nil,
        plannedCardCount: Int? = nil,
        attempt: Int? = nil,
        requestID: UUID? = nil
    ) -> AIDebugTraceScope {
        AIDebugTraceScope(
            runID: runID,
            kind: kind,
            targetType: targetType,
            sourceKind: sourceKind,
            providerName: providerName,
            modelName: modelName ?? self.modelName,
            operation: operation ?? self.operation,
            batchIndex: batchIndex ?? self.batchIndex,
            totalBatches: totalBatches ?? self.totalBatches,
            sourceLabel: sourceLabel ?? self.sourceLabel,
            plannedCardCount: plannedCardCount ?? self.plannedCardCount,
            attempt: attempt ?? self.attempt,
            requestID: requestID ?? self.requestID
        )
    }

    var metadata: [String: String] {
        var values: [String: String] = [
            "run_id": runID.uuidString,
            "run_kind": kind.rawValue,
            "target_type": targetType,
            "source_kind": sourceKind,
            "provider": providerName
        ]

        if let modelName, !modelName.isEmpty {
            values["model"] = modelName
        }
        if let operation, !operation.isEmpty {
            values["operation"] = operation
        }
        if let batchIndex {
            values["batch_index"] = String(batchIndex)
        }
        if let totalBatches {
            values["total_batches"] = String(totalBatches)
        }
        if let sourceLabel, !sourceLabel.isEmpty {
            values["source_label"] = sourceLabel
        }
        if let plannedCardCount {
            values["planned_card_count"] = String(plannedCardCount)
        }
        if let attempt {
            values["attempt"] = String(attempt)
        }
        if let requestID {
            values["request_id"] = requestID.uuidString
        }

        return values
    }
}

nonisolated struct AIDebugTraceRunSummary: Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let kind: AIDebugRunKind
    let targetType: String
    let sourceKind: String
    let targetCount: Int?
    let sourceCount: Int?
    let providerName: String
    let modelName: String?
    let status: String
    let eventCount: Int
    let lastStage: String?
    let durationMilliseconds: Int?
}

nonisolated struct AIDebugTraceRunDetail: Sendable {
    let summary: AIDebugTraceRunSummary
    let jsonString: String
}

nonisolated enum AIDebugTraceContext {
    @TaskLocal static var currentScope: AIDebugTraceScope?
}

private nonisolated struct AIDebugTraceRunMetadata: Codable {
    let runID: UUID
    let createdAt: Date
    let kind: String
    let targetType: String
    let sourceKind: String
    let targetCount: Int?
    let sourceCount: Int?
    let providerName: String
    let modelName: String?
    let metadata: [String: String]
}

private nonisolated struct AIDebugTraceEvent: Codable {
    let id: UUID
    let timestamp: Date
    let stage: String
    let message: String
    let metadata: [String: String]
    let payload: String?
}

private nonisolated struct AIDebugTraceRunExport: Codable {
    let metadata: AIDebugTraceRunMetadata
    let events: [AIDebugTraceEvent]
}

private nonisolated enum AIDebugTimedOperationKind: String, Sendable {
    case run
    case batch
    case request
    case decode
}

private nonisolated struct AIDebugTimedOperationKey: Hashable, Sendable {
    let runID: UUID
    let kind: AIDebugTimedOperationKind
    let discriminator: String
}

private nonisolated struct AIDebugTraceUsageTotals: Sendable {
    var responseCount = 0
    var promptTokens = 0
    var completionTokens = 0
    var totalTokens = 0
    var promptCacheHitTokens = 0
    var promptCacheMissTokens = 0
    var promptDetailsCachedTokens = 0
    var reasoningTokens = 0
    var estimatedCostMicroUSD = 0
}

actor AIDebugTraceStore {
    private static let runDirectoryTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static let shared = AIDebugTraceStore()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuizFlash",
        category: "AIDebugTrace"
    )
    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let eventEncoder: JSONEncoder
    private let decoder: JSONDecoder
    private let rootDirectoryURL: URL
    private var runDirectories: [UUID: URL] = [:]
    private var operationStartDates: [AIDebugTimedOperationKey: Date] = [:]
    private var usageTotals: [UUID: AIDebugTraceUsageTotals] = [:]

    init(
        fileManager: FileManager = .default,
        rootDirectoryURL: URL? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let eventEncoder = JSONEncoder()
        eventEncoder.dateEncodingStrategy = .iso8601
        self.eventEncoder = eventEncoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        if let rootDirectoryURL {
            self.rootDirectoryURL = rootDirectoryURL
        } else {
            let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.rootDirectoryURL = baseURL
                .appendingPathComponent("QuizFlash", isDirectory: true)
                .appendingPathComponent("ai_debug_traces", isDirectory: true)
        }
    }

    func isEnabled() -> Bool {
        guard AppFeatures.current.enablesAITraceTooling else {
            return false
        }

        return userDefaults.object(
            forKey: AIDebugTracePreferenceKeys.debugTracingEnabled
        ) as? Bool ?? true
    }

    func startRun(_ descriptor: AIDebugTraceRunDescriptor) async -> AIDebugTraceScope? {
        guard isEnabled() else { return nil }

        let runID = UUID()
        let directoryURL = runDirectoryURL(for: runID, kind: descriptor.kind)
        do {
            try ensureDirectoryExists(rootDirectoryURL)
            try ensureDirectoryExists(directoryURL)

            let metadata = AIDebugTraceRunMetadata(
                runID: runID,
                createdAt: Date(),
                kind: descriptor.kind.rawValue,
                targetType: descriptor.targetType,
                sourceKind: descriptor.sourceKind,
                targetCount: descriptor.targetCount,
                sourceCount: descriptor.sourceCount,
                providerName: descriptor.providerName,
                modelName: descriptor.modelName,
                metadata: descriptor.metadata
            )
            let metadataData = try encoder.encode(metadata)
            try metadataData.write(
                to: directoryURL.appendingPathComponent("metadata.json"),
                options: [.atomic]
            )

            runDirectories[runID] = directoryURL

            let scope = AIDebugTraceScope(
                runID: runID,
                kind: descriptor.kind,
                targetType: descriptor.targetType,
                sourceKind: descriptor.sourceKind,
                providerName: descriptor.providerName,
                modelName: descriptor.modelName
            )

            await record(
                stage: .runStarted,
                message: "Started AI \(descriptor.kind.rawValue) run.",
                scope: scope,
                metadata: descriptor.metadata
            )
            return scope
        } catch {
            logger.error("Failed to start AI debug trace run: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func finishRun(
        scope: AIDebugTraceScope,
        succeeded: Bool,
        metadata: [String: String] = [:],
        error: Error? = nil
    ) async {
        let message = succeeded
            ? "Finished AI run successfully."
            : "AI run failed."
        await record(
            stage: succeeded ? .runCompleted : .runFailed,
            message: message,
            scope: scope,
            metadata: metadata.merging(error.map { ["error": String(describing: $0)] } ?? [:]) { _, new in new }
        )
    }

    func record(
        stage: AIDebugTraceStage,
        message: String,
        scope: AIDebugTraceScope? = AIDebugTraceContext.currentScope,
        metadata: [String: String] = [:],
        payload: String? = nil
    ) async {
        guard isEnabled(), let scope else { return }

        let timestamp = Date()
        var mergedMetadata = scope.metadata.merging(metadata) { _, new in new }
        mergedMetadata.merge(timingMetadata(for: stage, scope: scope, timestamp: timestamp)) { _, new in new }
        if stage == .responseReceived {
            accumulateUsage(from: mergedMetadata, runID: scope.runID)
        } else if stage == .runCompleted || stage == .runFailed {
            mergedMetadata.merge(usageSummaryMetadata(for: scope.runID)) { _, new in new }
        }
        let event = AIDebugTraceEvent(
            id: UUID(),
            timestamp: timestamp,
            stage: stage.rawValue,
            message: message,
            metadata: mergedMetadata,
            payload: payload
        )

        do {
            let directoryURL = try directoryURL(for: scope.runID)
            let data = try eventEncoder.encode(event)
            var payloadData = data
            payloadData.append(0x0A)
            let eventsURL = directoryURL.appendingPathComponent("events.jsonl")
            if fileManager.fileExists(atPath: eventsURL.path) {
                let handle = try FileHandle(forWritingTo: eventsURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: payloadData)
            } else {
                try payloadData.write(to: eventsURL, options: [.atomic])
            }

            let prefix = String(scope.runID.uuidString.prefix(8))
            logger.debug("[AITrace][\(prefix, privacy: .public)][\(stage.rawValue, privacy: .public)] \(message, privacy: .public)")
            registerTimingStartIfNeeded(for: stage, scope: scope, timestamp: timestamp)
            if stage == .runCompleted || stage == .runFailed {
                usageTotals.removeValue(forKey: scope.runID)
            }
        } catch {
            logger.error("Failed to write AI debug trace event: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clearAllTraces() async {
        guard AppFeatures.current.enablesAITraceTooling else { return }
        guard fileManager.fileExists(atPath: rootDirectoryURL.path) else { return }
        do {
            try fileManager.removeItem(at: rootDirectoryURL)
            runDirectories.removeAll()
            operationStartDates.removeAll()
            usageTotals.removeAll()
        } catch {
            logger.error("Failed to clear AI debug traces: \(error.localizedDescription, privacy: .public)")
        }
    }

    func listRuns() async -> [AIDebugTraceRunSummary] {
        guard AppFeatures.current.enablesAITraceTooling else { return [] }
        guard fileManager.fileExists(atPath: rootDirectoryURL.path) else { return [] }

        do {
            let directories = try fileManager.contentsOfDirectory(
                at: rootDirectoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            var summaries: [AIDebugTraceRunSummary] = []
            summaries.reserveCapacity(directories.count)

            for directoryURL in directories {
                guard let summary = try loadSummary(from: directoryURL) else { continue }
                summaries.append(summary)
                runDirectories[summary.id] = directoryURL
            }

            return summaries.sorted { $0.createdAt > $1.createdAt }
        } catch {
            logger.error("Failed to list AI debug traces: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func loadRunDetail(id: UUID) async -> AIDebugTraceRunDetail? {
        guard AppFeatures.current.enablesAITraceTooling else { return nil }
        do {
            let directoryURL = try directoryURL(for: id)
            let metadataURL = directoryURL.appendingPathComponent("metadata.json")
            let eventsURL = directoryURL.appendingPathComponent("events.jsonl")

            let metadataData = try Data(contentsOf: metadataURL)
            let metadata = try decoder.decode(AIDebugTraceRunMetadata.self, from: metadataData)
            let events = try loadEvents(from: eventsURL)
            let summary = buildSummary(metadata: metadata, events: events)

            let export = AIDebugTraceRunExport(metadata: metadata, events: events)
            let exportData = try encoder.encode(export)
            guard let jsonString = String(data: exportData, encoding: .utf8) else {
                return nil
            }

            return AIDebugTraceRunDetail(summary: summary, jsonString: jsonString)
        } catch {
            logger.error("Failed to load AI debug trace detail: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func runDirectoryURL(for runID: UUID, kind: AIDebugRunKind) -> URL {
        let timestamp = Self.runDirectoryTimestampFormatter
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return rootDirectoryURL.appendingPathComponent("\(timestamp)_\(kind.rawValue)_\(runID.uuidString)", isDirectory: true)
    }

    private func directoryURL(for runID: UUID) throws -> URL {
        if let existing = runDirectories[runID] {
            return existing
        }

        try ensureDirectoryExists(rootDirectoryURL)
        let matches = try fileManager.contentsOfDirectory(
            at: rootDirectoryURL,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains(runID.uuidString) }

        if let first = matches.first {
            runDirectories[runID] = first
            return first
        }

        throw NSError(
            domain: "QuizFlashAIDebugTraceStore",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing trace directory for run \(runID.uuidString)."]
        )
    }

    private func ensureDirectoryExists(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func loadSummary(from directoryURL: URL) throws -> AIDebugTraceRunSummary? {
        let metadataURL = directoryURL.appendingPathComponent("metadata.json")
        guard fileManager.fileExists(atPath: metadataURL.path) else { return nil }

        let metadataData = try Data(contentsOf: metadataURL)
        let metadata = try decoder.decode(AIDebugTraceRunMetadata.self, from: metadataData)
        let events = try loadEvents(from: directoryURL.appendingPathComponent("events.jsonl"))
        return buildSummary(metadata: metadata, events: events)
    }

    private func loadEvents(from eventsURL: URL) throws -> [AIDebugTraceEvent] {
        guard fileManager.fileExists(atPath: eventsURL.path) else { return [] }

        let data = try Data(contentsOf: eventsURL)
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        return extractEventJSONChunks(from: text).compactMap { chunk in
            try? decoder.decode(AIDebugTraceEvent.self, from: chunk)
        }
    }

    private func buildSummary(
        metadata: AIDebugTraceRunMetadata,
        events: [AIDebugTraceEvent]
    ) -> AIDebugTraceRunSummary {
        let kind = AIDebugRunKind(rawValue: metadata.kind) ?? .utility
        let lastStage = events.last?.stage
        let status: String

        switch lastStage {
        case AIDebugTraceStage.runCompleted.rawValue:
            status = "completed"
        case AIDebugTraceStage.runFailed.rawValue:
            status = "failed"
        default:
            status = "in_progress"
        }

        return AIDebugTraceRunSummary(
            id: metadata.runID,
            createdAt: metadata.createdAt,
            kind: kind,
            targetType: metadata.targetType,
            sourceKind: metadata.sourceKind,
            targetCount: metadata.targetCount,
            sourceCount: metadata.sourceCount,
            providerName: metadata.providerName,
            modelName: metadata.modelName,
            status: status,
            eventCount: events.count,
            lastStage: lastStage,
            durationMilliseconds: extractRunDurationMilliseconds(from: events)
        )
    }

    private func registerTimingStartIfNeeded(
        for stage: AIDebugTraceStage,
        scope: AIDebugTraceScope,
        timestamp: Date
    ) {
        guard let key = timingKeyToStart(for: stage, scope: scope) else { return }
        operationStartDates[key] = timestamp
    }

    private func timingMetadata(
        for stage: AIDebugTraceStage,
        scope: AIDebugTraceScope,
        timestamp: Date
    ) -> [String: String] {
        guard let (key, metadataKey) = timingKeyToComplete(for: stage, scope: scope),
              let startedAt = operationStartDates.removeValue(forKey: key) else {
            return [:]
        }

        let elapsedMilliseconds = max(0, Int(timestamp.timeIntervalSince(startedAt) * 1000))
        return [metadataKey: String(elapsedMilliseconds)]
    }

    private func timingKeyToStart(
        for stage: AIDebugTraceStage,
        scope: AIDebugTraceScope
    ) -> AIDebugTimedOperationKey? {
        switch stage {
        case .runStarted:
            return AIDebugTimedOperationKey(
                runID: scope.runID,
                kind: .run,
                discriminator: scope.runID.uuidString
            )
        case .batchStarted:
            return batchTimingKey(for: scope)
        case .requestPrepared:
            return requestTimingKey(for: scope)
        case .decodePrepared:
            return decodeTimingKey(for: scope)
        default:
            return nil
        }
    }

    private func timingKeyToComplete(
        for stage: AIDebugTraceStage,
        scope: AIDebugTraceScope
    ) -> (AIDebugTimedOperationKey, String)? {
        switch stage {
        case .runCompleted, .runFailed:
            return (
                AIDebugTimedOperationKey(
                    runID: scope.runID,
                    kind: .run,
                    discriminator: scope.runID.uuidString
                ),
                "run_elapsed_ms"
            )
        case .batchCompleted, .batchRecovered:
            guard let key = batchTimingKey(for: scope) else { return nil }
            return (key, "batch_elapsed_ms")
        case .responseReceived:
            guard let key = requestTimingKey(for: scope) else { return nil }
            return (key, "request_elapsed_ms")
        case .retryScheduled:
            guard let key = requestTimingKey(for: scope) else { return nil }
            return (key, "request_elapsed_ms")
        case .decodeSucceeded, .decodeFailed:
            guard let key = decodeTimingKey(for: scope) else { return nil }
            return (key, "decode_elapsed_ms")
        default:
            return nil
        }
    }

    private func batchTimingKey(for scope: AIDebugTraceScope) -> AIDebugTimedOperationKey? {
        guard let operation = scope.operation else { return nil }
        let batchIndex = scope.batchIndex.map(String.init) ?? "none"
        let attempt = scope.attempt.map(String.init) ?? "none"
        let sourceLabel = scope.sourceLabel ?? "none"
        return AIDebugTimedOperationKey(
            runID: scope.runID,
            kind: .batch,
            discriminator: "\(operation)|\(batchIndex)|\(attempt)|\(sourceLabel)"
        )
    }

    private func requestTimingKey(for scope: AIDebugTraceScope) -> AIDebugTimedOperationKey? {
        guard let requestID = scope.requestID else { return nil }
        return AIDebugTimedOperationKey(
            runID: scope.runID,
            kind: .request,
            discriminator: requestID.uuidString
        )
    }

    private func decodeTimingKey(for scope: AIDebugTraceScope) -> AIDebugTimedOperationKey? {
        let discriminator = scope.requestID?.uuidString ?? [
            scope.operation ?? "decode",
            scope.batchIndex.map(String.init) ?? "none",
            scope.attempt.map(String.init) ?? "none"
        ].joined(separator: "|")
        return AIDebugTimedOperationKey(
            runID: scope.runID,
            kind: .decode,
            discriminator: discriminator
        )
    }

    private func extractRunDurationMilliseconds(
        from events: [AIDebugTraceEvent]
    ) -> Int? {
        if let terminalEvent = events.last(where: {
            $0.stage == AIDebugTraceStage.runCompleted.rawValue || $0.stage == AIDebugTraceStage.runFailed.rawValue
        }),
           let value = terminalEvent.metadata["run_elapsed_ms"],
           let milliseconds = Int(value) {
            return milliseconds
        }

        guard let first = events.first?.timestamp, let last = events.last?.timestamp else { return nil }
        return max(0, Int(last.timeIntervalSince(first) * 1000))
    }

    private func accumulateUsage(from metadata: [String: String], runID: UUID) {
        guard metadata["usage_keys"] != nil else { return }

        var totals = usageTotals[runID] ?? AIDebugTraceUsageTotals()
        totals.responseCount += 1
        totals.promptTokens += intValue(metadata["prompt_tokens"])
        totals.completionTokens += intValue(metadata["completion_tokens"])
        totals.totalTokens += intValue(metadata["total_tokens"])
        totals.promptCacheHitTokens += intValue(metadata["prompt_cache_hit_tokens"])
        totals.promptCacheMissTokens += intValue(metadata["prompt_cache_miss_tokens"])
        totals.promptDetailsCachedTokens += intValue(metadata["prompt_tokens_details_cached_tokens"])
        totals.reasoningTokens += intValue(metadata["completion_tokens_details_reasoning_tokens"])
        totals.estimatedCostMicroUSD += intValue(metadata["estimated_cost_micro_usd"])
        usageTotals[runID] = totals
    }

    private func usageSummaryMetadata(for runID: UUID) -> [String: String] {
        guard let totals = usageTotals[runID], totals.responseCount > 0 else { return [:] }

        return [
            "ai_usage_response_count": String(totals.responseCount),
            "ai_usage_prompt_tokens": String(totals.promptTokens),
            "ai_usage_completion_tokens": String(totals.completionTokens),
            "ai_usage_total_tokens": String(totals.totalTokens),
            "ai_usage_prompt_cache_hit_tokens": String(totals.promptCacheHitTokens),
            "ai_usage_prompt_cache_miss_tokens": String(totals.promptCacheMissTokens),
            "ai_usage_prompt_details_cached_tokens": String(totals.promptDetailsCachedTokens),
            "ai_usage_reasoning_tokens": String(totals.reasoningTokens),
            "ai_usage_estimated_cost_micro_usd": String(totals.estimatedCostMicroUSD)
        ]
    }

    private func intValue(_ value: String?) -> Int {
        guard let value else { return 0 }
        return Int(value) ?? 0
    }

    private func extractEventJSONChunks(from text: String) -> [Data] {
        var chunks: [Data] = []
        var objectStartIndex: String.Index?
        var depth = 0
        var isInString = false
        var isEscaped = false

        for index in text.indices {
            let character = text[index]

            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInString = false
                }
                continue
            }

            if character == "\"" {
                isInString = true
                continue
            }

            if character == "{" {
                if depth == 0 {
                    objectStartIndex = index
                }
                depth += 1
                continue
            }

            if character == "}" {
                guard depth > 0 else { continue }
                depth -= 1
                if depth == 0, let startIndex = objectStartIndex {
                    let endIndex = text.index(after: index)
                    let objectString = String(text[startIndex..<endIndex])
                    if let data = objectString.data(using: .utf8) {
                        chunks.append(data)
                    }
                    objectStartIndex = nil
                }
            }
        }

        return chunks
    }
}

extension AIFlashcardService {
    func withDebugRun<T: Sendable>(
        kind: AIDebugRunKind,
        targetType: String,
        sourceKind: String,
        targetCount: Int? = nil,
        sourceCount: Int? = nil,
        metadata: [String: String] = [:],
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
#if DEBUG
        if AIDebugTraceContext.currentScope != nil {
            return try await operation()
        }

        let descriptor = AIDebugTraceRunDescriptor(
            kind: kind,
            targetType: targetType,
            sourceKind: sourceKind,
            targetCount: targetCount,
            sourceCount: sourceCount,
            providerName: provider.trimmedName,
            modelName: nil,
            metadata: metadata
        )

        guard let scope = await debugTraceStore.startRun(descriptor) else {
            return try await operation()
        }

        do {
            let value = try await AIDebugTraceContext.$currentScope.withValue(scope) {
                try await operation()
            }
            await debugTraceStore.finishRun(scope: scope, succeeded: true)
            return value
        } catch {
            await debugTraceStore.finishRun(scope: scope, succeeded: false, error: error)
            throw error
        }
#else
        return try await operation()
#endif
    }

    func trace(
        _ stage: AIDebugTraceStage,
        _ message: @autoclosure () -> String,
        scope: AIDebugTraceScope? = AIDebugTraceContext.currentScope,
        metadata: @autoclosure () -> [String: String] = [:],
        payload: @autoclosure () -> String? = nil
    ) async {
#if DEBUG
        await debugTraceStore.record(
            stage: stage,
            message: message(),
            scope: scope,
            metadata: metadata(),
            payload: payload()
        )
#endif
    }

    func trace(
        stage: AIDebugTraceStage,
        message: @autoclosure () -> String,
        scope: AIDebugTraceScope? = AIDebugTraceContext.currentScope,
        metadata: @autoclosure () -> [String: String] = [:],
        payload: @autoclosure () -> String? = nil
    ) async {
#if DEBUG
        await trace(
            stage,
            message(),
            scope: scope,
            metadata: metadata(),
            payload: payload()
        )
#endif
    }

    func withTraceScope<T: Sendable>(
        _ scope: AIDebugTraceScope?,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        guard let scope else {
            return try await operation()
        }

        return try await AIDebugTraceContext.$currentScope.withValue(scope) {
            try await operation()
        }
    }
}
