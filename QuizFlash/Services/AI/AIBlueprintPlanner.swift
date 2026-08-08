import Foundation

nonisolated struct AIBlueprintProviderRequest: @unchecked Sendable {
    let messages: [[String: Any]]
    let maxCompletionTokens: Int
    let operation: String
}

typealias AIBlueprintProviderRequestHandler = @Sendable (AIBlueprintProviderRequest) async throws -> String

actor AIBlueprintPlanner {
    private struct SourceFragment: Codable, Sendable {
        let original_segment_index: Int
        let label: String
        let fragment_index: Int
        let fragment_count: Int
        let text: String
    }

    private let service: AIFlashcardService
    private let profile: AIBlueprintProviderProfile
    private let providerRequestHandler: AIBlueprintProviderRequestHandler?
    private let encoder: JSONEncoder

    init(
        service: AIFlashcardService,
        profile: AIBlueprintProviderProfile? = nil,
        providerRequestHandler: AIBlueprintProviderRequestHandler? = nil
    ) {
        self.service = service
        self.profile = profile ?? service.provider.blueprintProfile
        self.providerRequestHandler = providerRequestHandler
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
    }

    func build(
        segments: [AITextSourceSegment],
        targetCards: Int,
        options: AIGenerationOptions,
        manualAllocations: [AISourceRangeAllocation]
    ) async throws -> AISourceBlueprint {
        try Task.checkCancellation()
        let selectedSegments = selectedSourceSegments(
            segments,
            manualAllocations: manualAllocations
        )
        guard targetCards > 0, !selectedSegments.isEmpty else {
            throw AIServiceError.unknown("The source blueprint cannot be built from an empty source or target.")
        }

        let fingerprint = AIBlueprintValidator.sourceFingerprint(for: selectedSegments)
        let promptVersion = service.promptBundle?.version ?? "unversioned"
        let sourcePayload = try sourceJSON(selectedSegments)
        let constraintsPayload = try allocationJSON(manualAllocations)

        let initialDTO: AIBlueprintResponseDTO
        if conservativeTokenEstimate(sourcePayload) <= profile.directInputTokenBudget {
            await service.trace(
                .blueprintDirect,
                "Building a source blueprint in one request.",
                metadata: ["segment_count": String(selectedSegments.count), "target_cards": String(targetCards)]
            )
            initialDTO = try await request(
                messages: try service.buildBlueprintDirectMessages(
                    sourceJSON: sourcePayload,
                    allocationJSON: constraintsPayload,
                    targetCards: targetCards,
                    options: options,
                    sourceFingerprint: fingerprint,
                    promptVersion: promptVersion
                ),
                maxCompletionTokens: profile.maxOutputTokens(targetCards: targetCards),
                operation: "blueprint_reduce",
                as: AIBlueprintResponseDTO.self
            )
        } else {
            initialDTO = try await buildWithMapReduce(
                segments: selectedSegments,
                targetCards: targetCards,
                options: options,
                allocationJSON: constraintsPayload,
                sourceFingerprint: fingerprint,
                promptVersion: promptVersion
            )
        }

        return try await validateOrRepair(
            initialDTO,
            segments: selectedSegments,
            targetCards: targetCards,
            options: options,
            manualAllocations: manualAllocations,
            sourceFingerprint: fingerprint,
            promptVersion: promptVersion,
            sourceJSON: sourcePayload,
            allocationJSON: constraintsPayload
        )
    }

    private func buildWithMapReduce(
        segments: [AITextSourceSegment],
        targetCards: Int,
        options: AIGenerationOptions,
        allocationJSON: String,
        sourceFingerprint: String,
        promptVersion: String
    ) async throws -> AIBlueprintResponseDTO {
        let groups = try makeMapGroups(from: segments)
        await service.trace(
            .blueprintMap,
            "Mapping all source fragments for blueprint planning.",
            metadata: ["map_request_count": String(groups.count), "segment_count": String(segments.count)]
        )

        let digests = try await withThrowingTaskGroup(of: (Int, AIBlueprintMapDigest).self) { group in
            var nextIndex = 0
            var active = 0
            var results: [(Int, AIBlueprintMapDigest)] = []

            func schedule() {
                while active < profile.maxConcurrentMapRequests, nextIndex < groups.count {
                    let index = nextIndex
                    let sourceJSON = groups[index]
                    nextIndex += 1
                    active += 1
                    group.addTask { [self, service, profile] in
                        try Task.checkCancellation()
                        let digest = try await self.request(
                            messages: try service.buildBlueprintMapMessages(
                                sourceJSON: sourceJSON,
                                mapIndex: index + 1,
                                mapCount: groups.count,
                                options: options
                            ),
                            maxCompletionTokens: min(16_000, profile.maxOutputTokens(targetCards: targetCards)),
                            operation: "blueprint_map",
                            as: AIBlueprintMapDigest.self
                        )
                        return (index, digest)
                    }
                }
            }

            schedule()
            while let result = try await group.next() {
                active -= 1
                results.append(result)
                schedule()
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }

        return try await reduceToFinalBlueprint(
            digests,
            targetCards: targetCards,
            options: options,
            allocationJSON: allocationJSON,
            sourceFingerprint: sourceFingerprint,
            promptVersion: promptVersion
        )
    }

    private func reduceToFinalBlueprint(
        _ originalDigests: [AIBlueprintMapDigest],
        targetCards: Int,
        options: AIGenerationOptions,
        allocationJSON: String,
        sourceFingerprint: String,
        promptVersion: String
    ) async throws -> AIBlueprintResponseDTO {
        var digests = originalDigests
        var reduceLevel = 1

        while conservativeTokenEstimate(try json(digests)) > profile.reduceInputTokenBudget {
            let groups = try packedDigestGroups(digests)
            guard groups.count < digests.count else {
                throw AIServiceError.unknown("The blueprint reducer could not compact the source analysis safely.")
            }
            var compacted: [AIBlueprintMapDigest] = []
            for (index, digestGroup) in groups.enumerated() {
                try Task.checkCancellation()
                let digest = try await request(
                    messages: try service.buildBlueprintReduceMessages(
                        digestJSON: json(digestGroup),
                        allocationJSON: allocationJSON,
                        targetCards: targetCards,
                        options: options,
                        sourceFingerprint: sourceFingerprint,
                        promptVersion: promptVersion,
                        reduceLevel: reduceLevel,
                        isFinal: false,
                        groupIndex: index + 1,
                        groupCount: groups.count
                    ),
                    maxCompletionTokens: min(16_000, profile.maxOutputTokens(targetCards: targetCards)),
                    operation: "blueprint_reduce",
                    as: AIBlueprintMapDigest.self
                )
                compacted.append(digest)
            }
            digests = compacted
            reduceLevel += 1
        }

        await service.trace(
            .blueprintReduce,
            "Reducing source analysis into the final blueprint.",
            metadata: ["reduce_level": String(reduceLevel), "digest_count": String(digests.count)]
        )
        return try await request(
            messages: try service.buildBlueprintReduceMessages(
                digestJSON: json(digests),
                allocationJSON: allocationJSON,
                targetCards: targetCards,
                options: options,
                sourceFingerprint: sourceFingerprint,
                promptVersion: promptVersion,
                reduceLevel: reduceLevel,
                isFinal: true,
                groupIndex: 1,
                groupCount: 1
            ),
            maxCompletionTokens: profile.maxOutputTokens(targetCards: targetCards),
            operation: "blueprint_reduce",
            as: AIBlueprintResponseDTO.self
        )
    }

    private func validateOrRepair(
        _ initialDTO: AIBlueprintResponseDTO,
        segments: [AITextSourceSegment],
        targetCards: Int,
        options: AIGenerationOptions,
        manualAllocations: [AISourceRangeAllocation],
        sourceFingerprint: String,
        promptVersion: String,
        sourceJSON: String,
        allocationJSON: String
    ) async throws -> AISourceBlueprint {
        var dto = initialDTO
        var previousInvalidDTO: AIBlueprintResponseDTO?
        for repairAttempt in 0...2 {
            if let trimmedDTO = trimmingObjectiveSurplus(
                dto,
                targetCards: targetCards,
                manualAllocations: manualAllocations
            ) {
                let surplusCount = dto.objectives.count - trimmedDTO.objectives.count
                dto = trimmedDTO
                await service.trace(
                    .blueprintSurplusTrimmed,
                    "Trimmed valid surplus blueprint objectives locally.",
                    metadata: [
                        "surplus_count": String(surplusCount),
                        "target_cards": String(targetCards)
                    ]
                )
            }
            do {
                let blueprint = try AIBlueprintValidator.validate(
                    dto,
                    segments: segments,
                    targetCards: targetCards,
                    allocations: manualAllocations,
                    promptVersion: promptVersion,
                    sourceFingerprint: sourceFingerprint
                )
                await service.trace(
                    .blueprintValidated,
                    "Validated the source blueprint.",
                    metadata: [
                        "theme_count": String(blueprint.themes.count),
                        "objective_count": String(blueprint.objectives.count),
                        "repair_count": String(repairAttempt)
                    ]
                )
                return blueprint
            } catch let failure as AIBlueprintValidationFailure {
                var repairDiagnostics = failure.repairDiagnostics
                if let previousInvalidDTO, previousInvalidDTO == dto {
                    repairDiagnostics.append(.init(
                        code: "unchanged_candidate",
                        path: "$"
                    ))
                }
                await service.trace(
                    .blueprintValidationFailed,
                    "Blueprint validation requires semantic repair.",
                    metadata: [
                        "repair_attempt": String(repairAttempt),
                        "issue_count": String(failure.issues.count),
                        "issues": failure.issues.map(\.description).joined(separator: ","),
                        "diagnostic_count": String(repairDiagnostics.count)
                    ]
                )
                guard repairAttempt < 2 else {
                    throw AIServiceError.unknown("The source blueprint remained invalid after semantic repair.")
                }
                let invalidDTO = dto
                dto = try await request(
                    messages: try service.buildBlueprintRepairMessages(
                        invalidBlueprintJSON: json(dto),
                        issuesJSON: json(repairDiagnostics),
                        sourceJSON: sourceJSON,
                        allocationJSON: allocationJSON,
                        targetCards: targetCards,
                        options: options,
                        sourceFingerprint: sourceFingerprint,
                        promptVersion: promptVersion
                    ),
                    maxCompletionTokens: profile.maxOutputTokens(targetCards: targetCards),
                    operation: "blueprint_repair",
                    as: AIBlueprintResponseDTO.self
                )
                await service.trace(
                    .blueprintRepair,
                    "Received a repaired blueprint candidate.",
                    metadata: ["repair_attempt": String(repairAttempt + 1)]
                )
                previousInvalidDTO = invalidDTO
            }
        }
        throw AIServiceError.invalidResponse
    }

    private func trimmingObjectiveSurplus(
        _ dto: AIBlueprintResponseDTO,
        targetCards: Int,
        manualAllocations: [AISourceRangeAllocation]
    ) -> AIBlueprintResponseDTO? {
        guard manualAllocations.isEmpty,
              targetCards > 0,
              dto.objectives.count > targetCards,
              !dto.themes.isEmpty,
              dto.themes.count <= targetCards,
              Set(dto.themes.map(\.id)).count == dto.themes.count,
              Set(dto.objectives.map(\.id)).count == dto.objectives.count else {
            return nil
        }

        let themeIDs = Set(dto.themes.map(\.id))
        let indexedObjectives = Array(dto.objectives.enumerated())
        guard indexedObjectives.allSatisfy({ themeIDs.contains($0.element.theme_id) }) else {
            return nil
        }

        let candidatesByTheme = Dictionary(grouping: indexedObjectives) { $0.element.theme_id }
        guard dto.themes.allSatisfy({ !(candidatesByTheme[$0.id] ?? []).isEmpty }) else {
            return nil
        }

        // Preserve one objective per discovered theme, then distribute the remaining
        // capacity by candidate breadth. Source order is the only tie-breaker;
        // provider priority values never decide what source material is retained.
        let remainingSlots = targetCards - dto.themes.count
        let extraCapacityByTheme = Dictionary(uniqueKeysWithValues: dto.themes.map { theme in
            (theme.id, max((candidatesByTheme[theme.id]?.count ?? 0) - 1, 0))
        })
        let totalExtraCapacity = extraCapacityByTheme.values.reduce(0, +)
        guard remainingSlots == 0 || totalExtraCapacity > 0 else { return nil }

        var quotaByTheme = Dictionary(uniqueKeysWithValues: dto.themes.map { ($0.id, 1) })
        var remainders: [(themeID: Int, sourceOrder: Int, value: Int)] = []
        var allocatedExtra = 0

        if remainingSlots > 0 {
            for (sourceOrder, theme) in dto.themes.enumerated() {
                let capacity = extraCapacityByTheme[theme.id] ?? 0
                let scaledShare = remainingSlots * capacity
                let baseShare = min(capacity, scaledShare / totalExtraCapacity)
                quotaByTheme[theme.id, default: 1] += baseShare
                allocatedExtra += baseShare
                if baseShare < capacity {
                    remainders.append((theme.id, sourceOrder, scaledShare % totalExtraCapacity))
                }
            }

            var slotsToAllocate = remainingSlots - allocatedExtra
            for remainder in remainders.sorted(by: {
                $0.value == $1.value ? $0.sourceOrder < $1.sourceOrder : $0.value > $1.value
            }) where slotsToAllocate > 0 {
                quotaByTheme[remainder.themeID, default: 1] += 1
                slotsToAllocate -= 1
            }
            guard slotsToAllocate == 0 else { return nil }
        }

        var selectedIndexes = Set<Int>()
        for theme in dto.themes {
            guard let candidates = candidatesByTheme[theme.id],
                  let quota = quotaByTheme[theme.id],
                  quota > 0,
                  quota <= candidates.count else {
                return nil
            }
            for candidate in evenlySpacedSelection(candidates, count: quota) {
                selectedIndexes.insert(candidate.offset)
            }
        }
        guard selectedIndexes.count == targetCards else { return nil }

        return AIBlueprintResponseDTO(
            schema_version: dto.schema_version,
            suggested_title: dto.suggested_title,
            language_code: dto.language_code,
            language_display_name: dto.language_display_name,
            themes: dto.themes,
            objectives: indexedObjectives.compactMap { indexed in
                selectedIndexes.contains(indexed.offset) ? indexed.element : nil
            }
        )
    }

    private func evenlySpacedSelection<Element>(_ values: [Element], count: Int) -> [Element] {
        guard count > 0, count < values.count else { return count == values.count ? values : [] }
        guard count > 1 else { return [values[values.count / 2]] }

        return (0..<count).map { position in
            let index = position * (values.count - 1) / (count - 1)
            return values[index]
        }
    }

    private func selectedSourceSegments(
        _ segments: [AITextSourceSegment],
        manualAllocations: [AISourceRangeAllocation]
    ) -> [AITextSourceSegment] {
        guard !manualAllocations.isEmpty else { return segments.sorted { $0.index < $1.index } }
        let selected = Set(manualAllocations.flatMap { Array($0.startIndex...$0.endIndex) })
        return segments.filter { selected.contains($0.index) }.sorted { $0.index < $1.index }
    }

    private func request<T: Decodable & Sendable>(
        messages: [[String: Any]],
        maxCompletionTokens: Int,
        operation: String,
        as type: T.Type
    ) async throws -> T {
        if let providerRequestHandler {
            let content = try await providerRequestHandler(
                AIBlueprintProviderRequest(
                    messages: messages,
                    maxCompletionTokens: maxCompletionTokens,
                    operation: operation
                )
            )
            return try JSONDecoder().decode(type, from: Data(content.utf8))
        }
        return try await service.sendBlueprintRequest(
            messages: messages,
            maxCompletionTokens: maxCompletionTokens,
            operation: operation,
            as: type
        )
    }

    private func makeMapGroups(from segments: [AITextSourceSegment]) throws -> [String] {
        let fragments = segments.flatMap(splitForMap)
        var groups: [[SourceFragment]] = []
        var current: [SourceFragment] = []
        var currentTokens = 0
        let payloadBudget = mapPayloadTokenBudget

        for fragment in fragments {
            let tokens = mapTokenCost(fragment)
            if !current.isEmpty, currentTokens + tokens > payloadBudget {
                groups.append(current)
                current = []
                currentTokens = 0
            }
            current.append(fragment)
            currentTokens += tokens
        }
        if !current.isEmpty { groups.append(current) }
        return try groups.map(json)
    }

    private func splitForMap(_ segment: AITextSourceSegment) -> [SourceFragment] {
        let text = segment.text
        let metadataTokens = conservativeTokenEstimate(segment.label) + 128
        let availableTextTokens = max(1, mapPayloadTokenBudget - metadataTokens)
        guard conservativeTokenEstimate(text) > availableTextTokens else {
            return [SourceFragment(
                original_segment_index: segment.index,
                label: segment.label,
                fragment_index: 1,
                fragment_count: 1,
                text: text
            )]
        }

        var pieces: [String] = []
        let maximumUTF8Bytes = availableTextTokens * 2
        var current = ""
        var currentBytes = 0
        for character in text {
            let value = String(character)
            let valueBytes = value.utf8.count
            if !current.isEmpty, currentBytes + valueBytes > maximumUTF8Bytes {
                pieces.append(current)
                current = ""
                currentBytes = 0
            }
            current.append(character)
            currentBytes += valueBytes
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces.enumerated().map { index, piece in
            SourceFragment(
                original_segment_index: segment.index,
                label: segment.label,
                fragment_index: index + 1,
                fragment_count: pieces.count,
                text: piece
            )
        }
    }

    private var mapPayloadTokenBudget: Int {
        max(1, profile.mapInputTokenBudget - 1_024)
    }

    private func mapTokenCost(_ fragment: SourceFragment) -> Int {
        conservativeTokenEstimate(fragment.text) +
            conservativeTokenEstimate(fragment.label) +
            128
    }

    private func packedDigestGroups(_ digests: [AIBlueprintMapDigest]) throws -> [[AIBlueprintMapDigest]] {
        var groups: [[AIBlueprintMapDigest]] = []
        var current: [AIBlueprintMapDigest] = []
        var tokens = 0
        for digest in digests {
            let digestTokens = conservativeTokenEstimate(try json(digest)) + 256
            if !current.isEmpty, tokens + digestTokens > profile.reduceInputTokenBudget {
                groups.append(current)
                current = []
                tokens = 0
            }
            current.append(digest)
            tokens += digestTokens
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    private func sourceJSON(_ segments: [AITextSourceSegment]) throws -> String {
        try json(segments.map {
            SourceFragment(
                original_segment_index: $0.index,
                label: $0.label,
                fragment_index: 1,
                fragment_count: 1,
                text: $0.text
            )
        })
    }

    private func allocationJSON(_ allocations: [AISourceRangeAllocation]) throws -> String {
        struct Constraint: Codable {
            let allocation_index: Int
            let start_segment_index: Int
            let end_segment_index: Int
            let objective_count: Int
        }
        return try json(allocations.enumerated().map { index, allocation in
            Constraint(
                allocation_index: index + 1,
                start_segment_index: allocation.startIndex,
                end_segment_index: allocation.endIndex,
                objective_count: allocation.cardCount
            )
        })
    }

    private func conservativeTokenEstimate(_ string: String) -> Int {
        (string.utf8.count + 1) / 2
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

extension AIFlashcardService {
    func buildSourceBlueprint(
        segments: [AITextSourceSegment],
        targetCards: Int,
        options: AIGenerationOptions,
        manualAllocations: [AISourceRangeAllocation]
    ) async throws -> AISourceBlueprint {
        try await AIBlueprintPlanner(service: self).build(
            segments: segments,
            targetCards: targetCards,
            options: options,
            manualAllocations: manualAllocations
        )
    }
}
