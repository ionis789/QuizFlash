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

    private struct CoverageSupplementPlan: Codable, Sendable {
        let themes: [Theme]

        struct Theme: Codable, Sendable {
            let theme_id: Int
            let theme_title: String
            let requested_objectives: Int
            let focus_segment_indexes: [Int]
        }
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
            initialDTO = try await requestFinalBlueprint(
                messages: try service.buildBlueprintDirectMessages(
                    sourceJSON: sourcePayload,
                    allocationJSON: constraintsPayload,
                    targetCards: targetCards,
                    options: options,
                    sourceFingerprint: fingerprint,
                    promptVersion: promptVersion
                ),
                maxCompletionTokens: profile.maxOutputTokens(targetCards: targetCards),
                operation: "blueprint_reduce"
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
        return try await requestFinalBlueprint(
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
            operation: "blueprint_reduce"
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
                let declaredSegmentCount = Set(dto.themes.flatMap(\.source_segment_indexes)).count
                let retainedSegmentCount = Set(trimmedDTO.themes.flatMap(\.source_segment_indexes)).count
                dto = trimmedDTO
                await service.trace(
                    .blueprintSurplusTrimmed,
                    "Compacted valid surplus blueprint objectives locally.",
                    metadata: [
                        "surplus_count": String(surplusCount),
                        "target_cards": String(targetCards),
                        "declared_segment_count": String(declaredSegmentCount),
                        "retained_segment_count": String(retainedSegmentCount)
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
                if repairAttempt == 0,
                   let supplementPlan = coverageSupplementPlan(
                       for: dto,
                       failure: failure,
                       targetCards: targetCards,
                       manualAllocations: manualAllocations
                   ) {
                    do {
                        dto = try await applyingCoverageSupplement(
                            supplementPlan,
                            to: dto,
                            segments: segments,
                            targetCards: targetCards,
                            options: options,
                            manualAllocations: manualAllocations
                        )
                        await service.trace(
                            .blueprintRepair,
                            "Completed a focused blueprint coverage supplement.",
                            metadata: [
                                "repair_attempt": String(repairAttempt + 1),
                                "repair_mode": "coverage_supplement",
                                "supplement_theme_count": String(supplementPlan.themes.count),
                                "supplement_objective_count": String(
                                    supplementPlan.themes.reduce(0) { $0 + $1.requested_objectives }
                                )
                            ]
                        )
                        previousInvalidDTO = invalidDTO
                        continue
                    } catch {
                        try Task.checkCancellation()
                        await service.trace(
                            .blueprintValidationFailed,
                            "Focused blueprint coverage supplement failed; using complete semantic repair.",
                            metadata: [
                                "repair_attempt": String(repairAttempt),
                                "repair_mode": "coverage_supplement_fallback",
                                "error": String(describing: error)
                            ]
                        )
                    }
                }
                dto = try await requestFinalBlueprint(
                    messages: try service.buildBlueprintRepairMessages(
                        invalidBlueprintJSON: compactJSON(dto),
                        issuesJSON: json(repairDiagnostics),
                        sourceJSON: sourceJSON,
                        allocationJSON: allocationJSON,
                        targetCards: targetCards,
                        options: options,
                        sourceFingerprint: sourceFingerprint,
                        promptVersion: promptVersion
                    ),
                    maxCompletionTokens: profile.maxOutputTokens(targetCards: targetCards),
                    operation: "blueprint_repair"
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

        let candidateCapacityByTheme = Dictionary(uniqueKeysWithValues: dto.themes.map { theme in
            (theme.id, candidatesByTheme[theme.id]?.count ?? 0)
        })
        guard let quotaByTheme = neutralThemeQuotas(
            dto.themes,
            targetCards: targetCards,
            capacityByTheme: candidateCapacityByTheme
        ) else {
            return nil
        }

        var selectedIndexes = Set<Int>()
        for theme in dto.themes {
            guard let candidates = candidatesByTheme[theme.id],
                  let quota = quotaByTheme[theme.id],
                  quota > 0,
                  quota <= candidates.count else {
                return nil
            }
            for candidate in coverageMaximizingSelection(candidates, count: quota) {
                selectedIndexes.insert(candidate.offset)
            }
        }
        guard selectedIndexes.count == targetCards else { return nil }

        let selectedObjectives = indexedObjectives.compactMap { indexed in
            selectedIndexes.contains(indexed.offset) ? indexed.element : nil
        }
        let selectedIndexesByTheme = Dictionary(grouping: selectedObjectives, by: \.theme_id)
            .mapValues { objectives in
                Set(objectives.flatMap(\.source_segment_indexes))
            }
        let normalizedThemes = dto.themes.compactMap { theme -> AIBlueprintResponseDTO.Theme? in
            let retainedIndexes = selectedIndexesByTheme[theme.id, default: []]
                .intersection(theme.source_segment_indexes)
                .sorted()
            guard !retainedIndexes.isEmpty else { return nil }
            return .init(
                id: theme.id,
                title: theme.title,
                source_segment_indexes: retainedIndexes
            )
        }
        guard normalizedThemes.count == dto.themes.count else { return nil }

        return AIBlueprintResponseDTO(
            schema_version: dto.schema_version,
            suggested_title: dto.suggested_title,
            language_code: dto.language_code,
            language_display_name: dto.language_display_name,
            themes: normalizedThemes,
            objectives: selectedObjectives
        )
    }

    private func coverageSupplementPlan(
        for dto: AIBlueprintResponseDTO,
        failure: AIBlueprintValidationFailure,
        targetCards: Int,
        manualAllocations: [AISourceRangeAllocation]
    ) -> CoverageSupplementPlan? {
        guard manualAllocations.isEmpty,
              dto.objectives.count >= targetCards,
              !dto.themes.isEmpty,
              failure.issues.allSatisfy({ issue in
                  switch issue {
                  case .themeWithoutObjective, .uncoveredThemeSegments:
                      return true
                  case .wrongObjectiveCount(let expected, let actual):
                      return expected == targetCards && actual > targetCards
                  default:
                      return false
                  }
              }),
              Set(dto.themes.map(\.id)).count == dto.themes.count,
              Set(dto.objectives.map(\.id)).count == dto.objectives.count,
              let quotas = neutralThemeQuotas(dto.themes, targetCards: targetCards) else {
            return nil
        }

        let validThemeIDs = Set(dto.themes.map(\.id))
        guard dto.objectives.allSatisfy({ validThemeIDs.contains($0.theme_id) }) else {
            return nil
        }

        let objectivesByTheme = Dictionary(grouping: dto.objectives, by: \.theme_id)
        let plans = dto.themes.compactMap { theme -> CoverageSupplementPlan.Theme? in
            let themeIndexes = Set(theme.source_segment_indexes)
            let coveredIndexes = Set(
                objectivesByTheme[theme.id, default: []]
                    .flatMap(\.source_segment_indexes)
            )
            let uncoveredIndexes = themeIndexes.subtracting(coveredIndexes).sorted()
            let currentCount = objectivesByTheme[theme.id, default: []].count
            guard !uncoveredIndexes.isEmpty else { return nil }
            let requestedCount = max((quotas[theme.id] ?? 1) - currentCount, 1)
            return .init(
                theme_id: theme.id,
                theme_title: theme.title,
                requested_objectives: requestedCount,
                focus_segment_indexes: uncoveredIndexes
            )
        }
        guard !plans.isEmpty else { return nil }
        return CoverageSupplementPlan(themes: plans)
    }

    private func applyingCoverageSupplement(
        _ plan: CoverageSupplementPlan,
        to dto: AIBlueprintResponseDTO,
        segments: [AITextSourceSegment],
        targetCards: Int,
        options: AIGenerationOptions,
        manualAllocations: [AISourceRangeAllocation]
    ) async throws -> AIBlueprintResponseDTO {
        let requestedCountByTheme = Dictionary(uniqueKeysWithValues: plan.themes.map {
            ($0.theme_id, $0.requested_objectives)
        })
        let focusIndexesByTheme = Dictionary(uniqueKeysWithValues: plan.themes.map {
            ($0.theme_id, Set($0.focus_segment_indexes))
        })
        let gapIndexes = Set(plan.themes.flatMap(\.focus_segment_indexes))
        let gapSegments = segments.filter { gapIndexes.contains($0.index) }
        guard !gapSegments.isEmpty else { throw AIServiceError.invalidResponse }

        let expectedSupplementCount = requestedCountByTheme.values.reduce(0, +)
        let supplement: AIBlueprintSupplementResponseDTO = try await request(
            messages: try service.buildBlueprintSupplementMessages(
                supplementPlanJSON: json(plan),
                existingObjectivesJSON: json(AICompactBlueprintResponseDTO(dto).objectives),
                sourceJSON: sourceJSON(gapSegments),
                options: options
            ),
            maxCompletionTokens: min(2_048, 192 + expectedSupplementCount * 128),
            operation: "blueprint_repair",
            as: AIBlueprintSupplementResponseDTO.self
        )

        guard supplement.objectives.count == expectedSupplementCount else {
            throw AIServiceError.invalidResponse
        }
        let actualCountByTheme = Dictionary(grouping: supplement.objectives, by: \.themeID)
            .mapValues(\.count)
        guard actualCountByTheme == requestedCountByTheme else {
            throw AIServiceError.invalidResponse
        }

        var instructionIdentities = Set(dto.objectives.map {
            AIBlueprintValidator.textIdentity($0.instruction)
        })
        var nextID = (dto.objectives.map(\.id).max() ?? 0) + 1
        var additions: [AIBlueprintResponseDTO.Objective] = []
        for objective in supplement.objectives {
            let instruction = AIBlueprintValidator.mechanicallyNormalized(objective.instruction)
            let identity = AIBlueprintValidator.textIdentity(instruction)
            let indexes = AIBlueprintValidator.normalizedIndexes(objective.sourceSegmentIndexes)
            guard !instruction.isEmpty,
                  instruction.count <= 500,
                  instructionIdentities.insert(identity).inserted,
                  let focusIndexes = focusIndexesByTheme[objective.themeID],
                  !indexes.isEmpty,
                  Set(indexes).isSubset(of: focusIndexes) else {
                throw AIServiceError.invalidResponse
            }
            additions.append(
                .init(
                    id: nextID,
                    theme_id: objective.themeID,
                    instruction: instruction,
                    source_segment_indexes: indexes
                )
            )
            nextID += 1
        }

        let supplemented = AIBlueprintResponseDTO(
            schema_version: dto.schema_version,
            suggested_title: dto.suggested_title,
            language_code: dto.language_code,
            language_display_name: dto.language_display_name,
            themes: dto.themes,
            objectives: dto.objectives + additions
        )
        guard let trimmed = trimmingObjectiveSurplus(
            supplemented,
            targetCards: targetCards,
            manualAllocations: manualAllocations
        ) else {
            throw AIServiceError.invalidResponse
        }
        return trimmed
    }

    /// Assigns every theme one slot, then distributes remaining slots by the
    /// breadth of its declared source evidence. This is deterministic and does
    /// not infer which subject matter is more important.
    private func neutralThemeQuotas(
        _ themes: [AIBlueprintResponseDTO.Theme],
        targetCards: Int,
        capacityByTheme: [Int: Int]? = nil
    ) -> [Int: Int]? {
        guard !themes.isEmpty, themes.count <= targetCards else { return nil }
        if let capacityByTheme,
           themes.contains(where: { capacityByTheme[$0.id, default: 0] < 1 }) {
            return nil
        }
        var quotas = Dictionary(uniqueKeysWithValues: themes.map { ($0.id, 1) })
        let breadths = themes.map { max(Set($0.source_segment_indexes).count, 1) }
        var slotsToAllocate = targetCards - themes.count
        while slotsToAllocate > 0 {
            let eligibleIndexes = themes.indices.filter { index in
                guard let capacityByTheme else { return true }
                return quotas[themes[index].id, default: 1] < capacityByTheme[themes[index].id, default: 0]
            }
            guard var bestIndex = eligibleIndexes.first else { return nil }
            for candidateIndex in eligibleIndexes.dropFirst() {
                let bestDivisor = quotas[themes[bestIndex].id, default: 1] + 1
                let candidateDivisor = quotas[themes[candidateIndex].id, default: 1] + 1
                let candidateScore = breadths[candidateIndex] * bestDivisor
                let bestScore = breadths[bestIndex] * candidateDivisor
                if candidateScore > bestScore {
                    bestIndex = candidateIndex
                }
            }
            quotas[themes[bestIndex].id, default: 1] += 1
            slotsToAllocate -= 1
        }
        return quotas
    }

    /// Selects provider objectives by maximum new segment coverage. Evenly
    /// spaced source positions break coverage ties so no source prefix wins.
    private func coverageMaximizingSelection(
        _ values: [(offset: Int, element: AIBlueprintResponseDTO.Objective)],
        count: Int
    ) -> [(offset: Int, element: AIBlueprintResponseDTO.Objective)] {
        guard count > 0, count < values.count else { return count == values.count ? values : [] }
        let anchors = (0..<count).map { position in
            let localIndex = count == 1
                ? values.count / 2
                : position * (values.count - 1) / (count - 1)
            return values[localIndex].offset
        }
        var remaining = values
        var selected: [(offset: Int, element: AIBlueprintResponseDTO.Objective)] = []
        var coveredIndexes = Set<Int>()

        for anchor in anchors {
            var bestIndex = 0
            for candidateIndex in remaining.indices.dropFirst() {
                let candidate = remaining[candidateIndex]
                let current = remaining[bestIndex]
                let candidateGain = Set(candidate.element.source_segment_indexes)
                    .subtracting(coveredIndexes).count
                let currentGain = Set(current.element.source_segment_indexes)
                    .subtracting(coveredIndexes).count
                let candidateDistance = abs(candidate.offset - anchor)
                let currentDistance = abs(current.offset - anchor)
                if candidateGain > currentGain ||
                    (candidateGain == currentGain && candidateDistance < currentDistance) ||
                    (candidateGain == currentGain && candidateDistance == currentDistance && candidate.offset < current.offset) {
                    bestIndex = candidateIndex
                }
            }
            let chosen = remaining.remove(at: bestIndex)
            selected.append(chosen)
            coveredIndexes.formUnion(chosen.element.source_segment_indexes)
        }

        return selected.sorted { $0.offset < $1.offset }
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

    private func requestFinalBlueprint(
        messages: [[String: Any]],
        maxCompletionTokens: Int,
        operation: String
    ) async throws -> AIBlueprintResponseDTO {
        let compact: AICompactBlueprintResponseDTO = try await request(
            messages: messages,
            maxCompletionTokens: maxCompletionTokens,
            operation: operation,
            as: AICompactBlueprintResponseDTO.self
        )
        return compact.expanded
    }

    private func compactJSON(_ dto: AIBlueprintResponseDTO) throws -> String {
        try json(AICompactBlueprintResponseDTO(dto))
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
