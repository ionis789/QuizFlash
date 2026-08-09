import CryptoKit
import Foundation

nonisolated struct AIBlueprintProviderProfile: Equatable, Sendable {
    let contextTokenLimit: Int
    let directInputTokenBudget: Int
    let mapInputTokenBudget: Int
    let reduceInputTokenBudget: Int
    let maxConcurrentMapRequests: Int

    static let deepSeek = AIBlueprintProviderProfile(
        contextTokenLimit: 1_000_000,
        directInputTokenBudget: 700_000,
        mapInputTokenBudget: 120_000,
        reduceInputTokenBudget: 200_000,
        maxConcurrentMapRequests: 4
    )

    func maxOutputTokens(targetCards: Int) -> Int {
        min(20_000, 640 + max(targetCards, 1) * 144)
    }
}

extension AIProviderProfile {
    nonisolated var blueprintProfile: AIBlueprintProviderProfile { .deepSeek }
}

public nonisolated struct AISourceBlueprint: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let promptVersion: String
    let sourceFingerprint: String
    let suggestedTitle: String
    let dominantLanguage: AIGenerationLanguageHint?
    let themes: [AIBlueprintTheme]
    let objectives: [AIBlueprintObjective]
}

nonisolated struct AIBlueprintTheme: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let summary: String
    let sourceSegmentIndexes: [Int]
    let relativePriority: Int
}

nonisolated struct AIBlueprintObjective: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let themeID: UUID
    let instruction: String
    let sourceSegmentIndexes: [Int]
    let relativePriority: Int
    let sourceAllocationID: UUID?
}

nonisolated struct AIBlueprintBatchContext: Codable, Equatable, Sendable {
    let globalOutline: String
    let theme: AIBlueprintTheme
    let objectives: [AIBlueprintObjective]

    func limitingObjectives(to count: Int) -> AIBlueprintBatchContext {
        AIBlueprintBatchContext(
            globalOutline: globalOutline,
            theme: theme,
            objectives: Array(objectives.prefix(max(count, 0)))
        )
    }
}

nonisolated struct AIBlueprintResponseDTO: Codable, Equatable, Sendable {
    let schema_version: Int
    let suggested_title: String
    let language_code: String?
    let language_display_name: String?
    let themes: [Theme]
    let objectives: [Objective]

    nonisolated struct Theme: Codable, Equatable, Sendable {
        let id: Int
        let title: String
        let summary: String
        let source_segment_indexes: [Int]
        let relative_priority: Int
    }

    nonisolated struct Objective: Codable, Equatable, Sendable {
        let id: Int
        let theme_id: Int
        let instruction: String
        let source_segment_indexes: [Int]
        let relative_priority: Int
        let allocation_index: Int?
    }
}

/// Compact provider-only representation of a final blueprint response.
///
/// The planner expands this transport shape before deterministic validation so
/// compact wire keys never leak into the app's internal blueprint model.
nonisolated struct AICompactBlueprintResponseDTO: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let suggestedTitle: String
    let languageCode: String?
    let languageDisplayName: String?
    let themes: [Theme]
    let objectives: [Objective]

    nonisolated struct Theme: Codable, Equatable, Sendable {
        let id: Int
        let title: String
        let summary: String
        let sourceSegmentIndexes: [Int]
        let relativePriority: Int

        init(
            id: Int,
            title: String,
            summary: String,
            sourceSegmentIndexes: [Int],
            relativePriority: Int
        ) {
            self.id = id
            self.title = title
            self.summary = summary
            self.sourceSegmentIndexes = sourceSegmentIndexes
            self.relativePriority = relativePriority
        }

        init(from decoder: Decoder) throws {
            if var values = try? decoder.unkeyedContainer() {
                id = try values.decode(Int.self)
                title = try values.decode(String.self)
                summary = try values.decode(String.self)
                sourceSegmentIndexes = try values.decode([Int].self)
                relativePriority = try values.decode(Int.self)
                guard values.isAtEnd else {
                    throw DecodingError.dataCorruptedError(
                        in: values,
                        debugDescription: "A compact blueprint theme must contain exactly five values."
                    )
                }
                return
            }

            let values = try decoder.container(keyedBy: ObjectCodingKeys.self)
            id = try values.decode(Int.self, forKey: .id)
            title = try values.decode(String.self, forKey: .title)
            summary = try values.decode(String.self, forKey: .summary)
            sourceSegmentIndexes = try values.decode([Int].self, forKey: .sourceSegmentIndexes)
            relativePriority = try values.decode(Int.self, forKey: .relativePriority)
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.unkeyedContainer()
            try values.encode(id)
            try values.encode(title)
            try values.encode(summary)
            try values.encode(sourceSegmentIndexes)
            try values.encode(relativePriority)
        }

        private enum ObjectCodingKeys: String, CodingKey {
            case id
            case title
            case summary
            case sourceSegmentIndexes = "source_segment_indexes"
            case relativePriority = "relative_priority"
        }
    }

    nonisolated struct Objective: Codable, Equatable, Sendable {
        let id: Int
        let themeID: Int
        let instruction: String
        let sourceSegmentIndexes: [Int]
        let relativePriority: Int
        let allocationIndex: Int?

        init(
            id: Int,
            themeID: Int,
            instruction: String,
            sourceSegmentIndexes: [Int],
            relativePriority: Int,
            allocationIndex: Int?
        ) {
            self.id = id
            self.themeID = themeID
            self.instruction = instruction
            self.sourceSegmentIndexes = sourceSegmentIndexes
            self.relativePriority = relativePriority
            self.allocationIndex = allocationIndex
        }

        init(from decoder: Decoder) throws {
            if var values = try? decoder.unkeyedContainer() {
                id = try values.decode(Int.self)
                themeID = try values.decode(Int.self)
                instruction = try values.decode(String.self)
                sourceSegmentIndexes = try values.decode([Int].self)
                relativePriority = try values.decode(Int.self)
                allocationIndex = try values.decodeNil() ? nil : try values.decode(Int.self)
                guard values.isAtEnd else {
                    throw DecodingError.dataCorruptedError(
                        in: values,
                        debugDescription: "A compact blueprint objective must contain exactly six values."
                    )
                }
                return
            }

            let values = try decoder.container(keyedBy: ObjectCodingKeys.self)
            id = try values.decode(Int.self, forKey: .id)
            themeID = try values.decode(Int.self, forKey: .themeID)
            instruction = try values.decode(String.self, forKey: .instruction)
            sourceSegmentIndexes = try values.decode([Int].self, forKey: .sourceSegmentIndexes)
            relativePriority = try values.decode(Int.self, forKey: .relativePriority)
            allocationIndex = try values.decodeIfPresent(Int.self, forKey: .allocationIndex)
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.unkeyedContainer()
            try values.encode(id)
            try values.encode(themeID)
            try values.encode(instruction)
            try values.encode(sourceSegmentIndexes)
            try values.encode(relativePriority)
            try values.encode(allocationIndex)
        }

        private enum ObjectCodingKeys: String, CodingKey {
            case id
            case themeID = "theme_id"
            case instruction
            case sourceSegmentIndexes = "source_segment_indexes"
            case relativePriority = "relative_priority"
            case allocationIndex = "allocation_index"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "v"
        case suggestedTitle = "t"
        case languageCode = "lc"
        case languageDisplayName = "ln"
        case themes = "th"
        case objectives = "ob"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.languageCode), container.contains(.languageDisplayName) else {
            let missingKey = container.contains(.languageCode)
                ? CodingKeys.languageDisplayName
                : CodingKeys.languageCode
            throw DecodingError.keyNotFound(
                missingKey,
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Compact blueprint language fields are required and may be null."
                )
            )
        }
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        suggestedTitle = try container.decode(String.self, forKey: .suggestedTitle)
        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
        languageDisplayName = try container.decodeIfPresent(String.self, forKey: .languageDisplayName)
        themes = try container.decode([Theme].self, forKey: .themes)
        objectives = try container.decode([Objective].self, forKey: .objectives)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(suggestedTitle, forKey: .suggestedTitle)
        try container.encode(languageCode, forKey: .languageCode)
        try container.encode(languageDisplayName, forKey: .languageDisplayName)
        try container.encode(themes, forKey: .themes)
        try container.encode(objectives, forKey: .objectives)
    }

    init(_ dto: AIBlueprintResponseDTO) {
        schemaVersion = dto.schema_version
        suggestedTitle = dto.suggested_title
        languageCode = dto.language_code
        languageDisplayName = dto.language_display_name
        themes = dto.themes.map {
            Theme(
                id: $0.id,
                title: $0.title,
                summary: $0.summary,
                sourceSegmentIndexes: $0.source_segment_indexes,
                relativePriority: $0.relative_priority
            )
        }
        objectives = dto.objectives.map {
            Objective(
                id: $0.id,
                themeID: $0.theme_id,
                instruction: $0.instruction,
                sourceSegmentIndexes: $0.source_segment_indexes,
                relativePriority: $0.relative_priority,
                allocationIndex: $0.allocation_index
            )
        }
    }

    var expanded: AIBlueprintResponseDTO {
        AIBlueprintResponseDTO(
            schema_version: schemaVersion,
            suggested_title: suggestedTitle,
            language_code: languageCode,
            language_display_name: languageDisplayName,
            themes: themes.map {
                .init(
                    id: $0.id,
                    title: $0.title,
                    summary: $0.summary,
                    source_segment_indexes: $0.sourceSegmentIndexes,
                    relative_priority: $0.relativePriority
                )
            },
            objectives: objectives.map {
                .init(
                    id: $0.id,
                    theme_id: $0.themeID,
                    instruction: $0.instruction,
                    source_segment_indexes: $0.sourceSegmentIndexes,
                    relative_priority: $0.relativePriority,
                    allocation_index: $0.allocationIndex
                )
            }
        )
    }
}

nonisolated struct AIBlueprintMapDigest: Codable, Equatable, Sendable {
    let themes: [Theme]
    let objectives: [Objective]

    nonisolated struct Theme: Codable, Equatable, Sendable {
        let title: String
        let summary: String
        let source_segment_indexes: [Int]
        let relative_priority: Int
    }

    nonisolated struct Objective: Codable, Equatable, Sendable {
        let instruction: String
        let source_segment_indexes: [Int]
        let relative_priority: Int
    }
}

nonisolated enum AIBlueprintValidationIssue: Error, Hashable, Sendable, CustomStringConvertible {
    case unsupportedSchema
    case emptyTitle
    case titleTooLong
    case invalidLanguage
    case invalidThemeCount
    case duplicateThemeID
    case duplicateTheme
    case emptyTheme
    case themeTooLong
    case invalidThemeSegments
    case themeWithoutObjective
    case uncoveredThemeSegments
    case wrongObjectiveCount(expected: Int, actual: Int)
    case duplicateObjectiveID
    case emptyObjective
    case objectiveTooLong
    case duplicateObjective
    case invalidObjectiveTheme
    case invalidObjectiveSegments
    case invalidManualDistribution

    var description: String {
        switch self {
        case .unsupportedSchema: return "unsupported_schema"
        case .emptyTitle: return "empty_title"
        case .titleTooLong: return "title_too_long"
        case .invalidLanguage: return "invalid_language"
        case .invalidThemeCount: return "invalid_theme_count"
        case .duplicateThemeID: return "duplicate_theme_id"
        case .duplicateTheme: return "duplicate_theme"
        case .emptyTheme: return "empty_theme"
        case .themeTooLong: return "theme_too_long"
        case .invalidThemeSegments: return "invalid_theme_segments"
        case .themeWithoutObjective: return "theme_without_objective"
        case .uncoveredThemeSegments: return "uncovered_theme_segments"
        case .wrongObjectiveCount(let expected, let actual): return "wrong_objective_count_expected_\(expected)_actual_\(actual)"
        case .duplicateObjectiveID: return "duplicate_objective_id"
        case .emptyObjective: return "empty_objective"
        case .objectiveTooLong: return "objective_too_long"
        case .duplicateObjective: return "duplicate_objective"
        case .invalidObjectiveTheme: return "invalid_objective_theme"
        case .invalidObjectiveSegments: return "invalid_objective_segments"
        case .invalidManualDistribution: return "invalid_manual_distribution"
        }
    }
}

nonisolated struct AIBlueprintValidationFailure: Error, Sendable {
    let issues: [AIBlueprintValidationIssue]
    let repairDiagnostics: [AIBlueprintRepairDiagnostic]
}

nonisolated struct AIBlueprintRepairDiagnostic: Codable, Equatable, Hashable, Sendable {
    let code: String
    let path: String
    let entity_id: Int?
    let related_entity_id: Int?
    let minimum_integer: Int?
    let maximum_integer: Int?
    let expected_integer: Int?
    let actual_integer: Int?
    let expected_indexes: [Int]?
    let actual_indexes: [Int]?

    init(
        code: String,
        path: String,
        entityID: Int? = nil,
        relatedEntityID: Int? = nil,
        minimumInteger: Int? = nil,
        maximumInteger: Int? = nil,
        expectedInteger: Int? = nil,
        actualInteger: Int? = nil,
        expectedIndexes: [Int]? = nil,
        actualIndexes: [Int]? = nil
    ) {
        self.code = code
        self.path = path
        entity_id = entityID
        related_entity_id = relatedEntityID
        minimum_integer = minimumInteger
        maximum_integer = maximumInteger
        expected_integer = expectedInteger
        actual_integer = actualInteger
        expected_indexes = expectedIndexes
        actual_indexes = actualIndexes
    }
}

nonisolated enum AIBlueprintValidator {
    static let supportedSchemaVersion = 1

    static func validate(
        _ dto: AIBlueprintResponseDTO,
        segments: [AITextSourceSegment],
        targetCards: Int,
        allocations: [AISourceRangeAllocation],
        promptVersion: String,
        sourceFingerprint: String
    ) throws -> AISourceBlueprint {
        var issues: [AIBlueprintValidationIssue] = []
        var repairDiagnostics: [AIBlueprintRepairDiagnostic] = []
        let validSegmentIndexes = Set(segments.map(\.index))
        let sortedValidSegmentIndexes = validSegmentIndexes.sorted()
        let normalizedTitle = mechanicallyNormalized(dto.suggested_title)
        let languageHint = AIFlashcardService.normalizedLanguageHint(
            code: dto.language_code,
            displayName: dto.language_display_name
        )

        if dto.schema_version != supportedSchemaVersion {
            issues.append(.unsupportedSchema)
            repairDiagnostics.append(.init(
                code: AIBlueprintValidationIssue.unsupportedSchema.description,
                path: "schema_version",
                expectedInteger: supportedSchemaVersion,
                actualInteger: dto.schema_version
            ))
        }
        if normalizedTitle.isEmpty {
            issues.append(.emptyTitle)
            repairDiagnostics.append(.init(code: AIBlueprintValidationIssue.emptyTitle.description, path: "suggested_title"))
        }
        if normalizedTitle.count > 160 {
            issues.append(.titleTooLong)
            repairDiagnostics.append(.init(
                code: AIBlueprintValidationIssue.titleTooLong.description,
                path: "suggested_title",
                maximumInteger: 160,
                actualInteger: normalizedTitle.count
            ))
        }
        let hasLanguageValue = [dto.language_code, dto.language_display_name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { !$0.isEmpty }
        if hasLanguageValue, languageHint == nil {
            issues.append(.invalidLanguage)
            repairDiagnostics.append(.init(code: AIBlueprintValidationIssue.invalidLanguage.description, path: "language_code,language_display_name"))
        }
        if dto.themes.isEmpty || dto.themes.count > min(max(targetCards, 1), 64) {
            issues.append(.invalidThemeCount)
            repairDiagnostics.append(.init(
                code: AIBlueprintValidationIssue.invalidThemeCount.description,
                path: "themes",
                minimumInteger: 1,
                maximumInteger: min(max(targetCards, 1), 64),
                actualInteger: dto.themes.count
            ))
        }
        let duplicateThemeIDs = duplicateIntegers(in: dto.themes.map(\.id))
        if !duplicateThemeIDs.isEmpty {
            issues.append(.duplicateThemeID)
            repairDiagnostics.append(.init(
                code: AIBlueprintValidationIssue.duplicateThemeID.description,
                path: "themes[].id",
                actualIndexes: duplicateThemeIDs
            ))
        }
        if dto.objectives.count != targetCards {
            let issue = AIBlueprintValidationIssue.wrongObjectiveCount(expected: targetCards, actual: dto.objectives.count)
            issues.append(issue)
            repairDiagnostics.append(.init(
                code: issue.description,
                path: "objectives",
                expectedInteger: targetCards,
                actualInteger: dto.objectives.count
            ))
        }
        let duplicateObjectiveIDs = duplicateIntegers(in: dto.objectives.map(\.id))
        if !duplicateObjectiveIDs.isEmpty {
            issues.append(.duplicateObjectiveID)
            repairDiagnostics.append(.init(
                code: AIBlueprintValidationIssue.duplicateObjectiveID.description,
                path: "objectives[].id",
                actualIndexes: duplicateObjectiveIDs
            ))
        }

        let allocationByIndex = Dictionary(uniqueKeysWithValues: allocations.enumerated().map { ($0.offset + 1, $0.element) })
        let themeDTOByID = dto.themes.reduce(into: [Int: AIBlueprintResponseDTO.Theme]()) {
            $0[$1.id] = $1
        }

        var normalizedThemeTitleOwner: [String: Int] = [:]
        for theme in dto.themes {
            let title = mechanicallyNormalized(theme.title)
            let summary = mechanicallyNormalized(theme.summary)
            if title.isEmpty {
                issues.append(.emptyTheme)
                repairDiagnostics.append(.init(code: AIBlueprintValidationIssue.emptyTheme.description, path: "themes[id=\(theme.id)].title", entityID: theme.id))
            }
            if summary.isEmpty {
                issues.append(.emptyTheme)
                repairDiagnostics.append(.init(code: AIBlueprintValidationIssue.emptyTheme.description, path: "themes[id=\(theme.id)].summary", entityID: theme.id))
            }
            if title.count > 160 {
                issues.append(.themeTooLong)
                repairDiagnostics.append(.init(code: AIBlueprintValidationIssue.themeTooLong.description, path: "themes[id=\(theme.id)].title", entityID: theme.id, maximumInteger: 160, actualInteger: title.count))
            }
            if summary.count > 800 {
                issues.append(.themeTooLong)
                repairDiagnostics.append(.init(code: AIBlueprintValidationIssue.themeTooLong.description, path: "themes[id=\(theme.id)].summary", entityID: theme.id, maximumInteger: 800, actualInteger: summary.count))
            }
            let titleIdentity = textIdentity(title)
            if let existingID = normalizedThemeTitleOwner[titleIdentity] {
                issues.append(.duplicateTheme)
                repairDiagnostics.append(.init(code: AIBlueprintValidationIssue.duplicateTheme.description, path: "themes[id=\(theme.id)].title", entityID: theme.id, relatedEntityID: existingID))
            } else {
                normalizedThemeTitleOwner[titleIdentity] = theme.id
            }
            let indexes = normalizedIndexes(theme.source_segment_indexes)
            if indexes.isEmpty || !Set(indexes).isSubset(of: validSegmentIndexes) {
                issues.append(.invalidThemeSegments)
                repairDiagnostics.append(.init(
                    code: AIBlueprintValidationIssue.invalidThemeSegments.description,
                    path: "themes[id=\(theme.id)].source_segment_indexes",
                    entityID: theme.id,
                    expectedIndexes: sortedValidSegmentIndexes,
                    actualIndexes: indexes
                ))
            }
        }

        var normalizedInstructionOwner: [String: Int] = [:]
        let validThemeIDs = Set(dto.themes.map(\.id)).sorted()
        for objective in dto.objectives {
            let instruction = mechanicallyNormalized(objective.instruction)
            if instruction.isEmpty {
                issues.append(.emptyObjective)
                repairDiagnostics.append(.init(code: AIBlueprintValidationIssue.emptyObjective.description, path: "objectives[id=\(objective.id)].instruction", entityID: objective.id))
            }
            if instruction.count > 500 {
                issues.append(.objectiveTooLong)
                repairDiagnostics.append(.init(code: AIBlueprintValidationIssue.objectiveTooLong.description, path: "objectives[id=\(objective.id)].instruction", entityID: objective.id, maximumInteger: 500, actualInteger: instruction.count))
            }
            let instructionIdentity = textIdentity(instruction)
            if let existingID = normalizedInstructionOwner[instructionIdentity] {
                issues.append(.duplicateObjective)
                repairDiagnostics.append(.init(code: AIBlueprintValidationIssue.duplicateObjective.description, path: "objectives[id=\(objective.id)].instruction", entityID: objective.id, relatedEntityID: existingID))
            } else {
                normalizedInstructionOwner[instructionIdentity] = objective.id
            }
            guard let theme = themeDTOByID[objective.theme_id] else {
                issues.append(.invalidObjectiveTheme)
                repairDiagnostics.append(.init(
                    code: AIBlueprintValidationIssue.invalidObjectiveTheme.description,
                    path: "objectives[id=\(objective.id)].theme_id",
                    entityID: objective.id,
                    actualInteger: objective.theme_id,
                    expectedIndexes: validThemeIDs
                ))
                continue
            }
            let objectiveIndexes = normalizedIndexes(objective.source_segment_indexes)
            let themeIndexes = Set(normalizedIndexes(theme.source_segment_indexes))
            if objectiveIndexes.isEmpty ||
                !Set(objectiveIndexes).isSubset(of: validSegmentIndexes) ||
                !Set(objectiveIndexes).isSubset(of: themeIndexes) {
                issues.append(.invalidObjectiveSegments)
                repairDiagnostics.append(.init(
                    code: AIBlueprintValidationIssue.invalidObjectiveSegments.description,
                    path: "objectives[id=\(objective.id)].source_segment_indexes",
                    entityID: objective.id,
                    relatedEntityID: objective.theme_id,
                    expectedIndexes: themeIndexes.intersection(validSegmentIndexes).sorted(),
                    actualIndexes: objectiveIndexes
                ))
            }

            if !allocations.isEmpty {
                guard let allocationIndex = objective.allocation_index,
                      let allocation = allocationByIndex[allocationIndex] else {
                    issues.append(.invalidManualDistribution)
                    repairDiagnostics.append(.init(
                        code: AIBlueprintValidationIssue.invalidManualDistribution.description,
                        path: "objectives[id=\(objective.id)].allocation_index",
                        entityID: objective.id,
                        actualInteger: objective.allocation_index,
                        expectedIndexes: allocationByIndex.keys.sorted()
                    ))
                    continue
                }
                let allocationIndexes = Set(allocation.startIndex...allocation.endIndex)
                if !Set(objectiveIndexes).isSubset(of: allocationIndexes) {
                    issues.append(.invalidManualDistribution)
                    repairDiagnostics.append(.init(
                        code: AIBlueprintValidationIssue.invalidManualDistribution.description,
                        path: "objectives[id=\(objective.id)].source_segment_indexes",
                        entityID: objective.id,
                        relatedEntityID: allocationIndex,
                        expectedIndexes: allocationIndexes.sorted(),
                        actualIndexes: objectiveIndexes
                    ))
                }
            }
        }

        let representedThemeIDs = Set(dto.objectives.map(\.theme_id))
        for theme in dto.themes where !representedThemeIDs.contains(theme.id) {
            issues.append(.themeWithoutObjective)
            repairDiagnostics.append(.init(
                code: AIBlueprintValidationIssue.themeWithoutObjective.description,
                path: "themes[id=\(theme.id)].objectives",
                entityID: theme.id,
                minimumInteger: 1,
                actualInteger: 0
            ))
        }

        let coveredIndexesByTheme = Dictionary(grouping: dto.objectives, by: \.theme_id)
            .mapValues { objectives in
                Set(objectives.flatMap { normalizedIndexes($0.source_segment_indexes) })
            }
        for theme in dto.themes {
            let expectedIndexes = Set(normalizedIndexes(theme.source_segment_indexes))
            let actualIndexes = coveredIndexesByTheme[theme.id, default: []]
                .intersection(expectedIndexes)
            guard !expectedIndexes.subtracting(actualIndexes).isEmpty else { continue }
            issues.append(.uncoveredThemeSegments)
            repairDiagnostics.append(.init(
                code: AIBlueprintValidationIssue.uncoveredThemeSegments.description,
                path: "themes[id=\(theme.id)].source_segment_indexes",
                entityID: theme.id,
                expectedIndexes: expectedIndexes.sorted(),
                actualIndexes: actualIndexes.sorted()
            ))
        }

        if !allocations.isEmpty {
            for (allocationIndex, allocation) in allocationByIndex {
                let actual = dto.objectives.filter { $0.allocation_index == allocationIndex }.count
                if actual != allocation.cardCount {
                    issues.append(.invalidManualDistribution)
                    repairDiagnostics.append(.init(
                        code: AIBlueprintValidationIssue.invalidManualDistribution.description,
                        path: "objectives[].allocation_index",
                        entityID: allocationIndex,
                        expectedInteger: allocation.cardCount,
                        actualInteger: actual
                    ))
                }
            }
        }

        guard issues.isEmpty else {
            throw AIBlueprintValidationFailure(
                issues: Array(Set(issues)).sorted { $0.description < $1.description },
                repairDiagnostics: Array(Set(repairDiagnostics)).sorted {
                    ($0.path, $0.code, $0.entity_id ?? Int.min) < ($1.path, $1.code, $1.entity_id ?? Int.min)
                }
            )
        }

        let themeIDMap = Dictionary(uniqueKeysWithValues: dto.themes.map { ($0.id, UUID()) })
        let themes = dto.themes.map { theme in
            AIBlueprintTheme(
                id: themeIDMap[theme.id]!,
                title: mechanicallyNormalized(theme.title),
                summary: mechanicallyNormalized(theme.summary),
                sourceSegmentIndexes: normalizedIndexes(theme.source_segment_indexes),
                relativePriority: theme.relative_priority
            )
        }
        let objectives = dto.objectives.map { objective in
            AIBlueprintObjective(
                id: UUID(),
                themeID: themeIDMap[objective.theme_id]!,
                instruction: mechanicallyNormalized(objective.instruction),
                sourceSegmentIndexes: normalizedIndexes(objective.source_segment_indexes),
                relativePriority: objective.relative_priority,
                sourceAllocationID: objective.allocation_index.flatMap { allocationByIndex[$0]?.id }
            )
        }

        return AISourceBlueprint(
            schemaVersion: dto.schema_version,
            promptVersion: promptVersion,
            sourceFingerprint: sourceFingerprint,
            suggestedTitle: normalizedTitle,
            dominantLanguage: languageHint,
            themes: themes,
            objectives: objectives
        )
    }

    static func mechanicallyNormalized(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func normalizedIndexes(_ values: [Int]) -> [Int] {
        Array(Set(values)).sorted()
    }

    private static func duplicateIntegers(in values: [Int]) -> [Int] {
        var seen = Set<Int>()
        var duplicates = Set<Int>()
        for value in values where !seen.insert(value).inserted {
            duplicates.insert(value)
        }
        return duplicates.sorted()
    }

    static func textIdentity(_ value: String) -> String {
        mechanicallyNormalized(value).folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    static func sourceFingerprint(for segments: [AITextSourceSegment]) -> String {
        var bytes = Data()
        for segment in segments.sorted(by: { $0.index < $1.index }) {
            bytes.append(Data("\(segment.index)\u{1f}\(segment.label)\u{1f}".utf8))
            bytes.append(Data(segment.text.precomposedStringWithCanonicalMapping.utf8))
            bytes.append(0x1e)
        }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
