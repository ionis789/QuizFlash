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
        min(32_000, 1_024 + max(targetCards, 1) * 256)
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
        let validSegmentIndexes = Set(segments.map(\.index))
        let normalizedTitle = mechanicallyNormalized(dto.suggested_title)
        let languageHint = AIFlashcardService.normalizedLanguageHint(
            code: dto.language_code,
            displayName: dto.language_display_name
        )

        if dto.schema_version != supportedSchemaVersion { issues.append(.unsupportedSchema) }
        if normalizedTitle.isEmpty { issues.append(.emptyTitle) }
        if normalizedTitle.count > 160 { issues.append(.titleTooLong) }
        let hasLanguageValue = [dto.language_code, dto.language_display_name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { !$0.isEmpty }
        if hasLanguageValue, languageHint == nil { issues.append(.invalidLanguage) }
        if dto.themes.isEmpty || dto.themes.count > min(max(targetCards, 1), 64) {
            issues.append(.invalidThemeCount)
        }
        if Set(dto.themes.map(\.id)).count != dto.themes.count { issues.append(.duplicateThemeID) }
        if dto.objectives.count != targetCards {
            issues.append(.wrongObjectiveCount(expected: targetCards, actual: dto.objectives.count))
        }
        if Set(dto.objectives.map(\.id)).count != dto.objectives.count { issues.append(.duplicateObjectiveID) }

        let allocationByIndex = Dictionary(uniqueKeysWithValues: allocations.enumerated().map { ($0.offset + 1, $0.element) })
        let themeDTOByID = dto.themes.reduce(into: [Int: AIBlueprintResponseDTO.Theme]()) {
            $0[$1.id] = $1
        }

        var normalizedThemeTitles = Set<String>()
        for theme in dto.themes {
            let title = mechanicallyNormalized(theme.title)
            let summary = mechanicallyNormalized(theme.summary)
            if title.isEmpty || summary.isEmpty { issues.append(.emptyTheme) }
            if title.count > 160 || summary.count > 800 { issues.append(.themeTooLong) }
            if !normalizedThemeTitles.insert(textIdentity(title)).inserted {
                issues.append(.duplicateTheme)
            }
            let indexes = normalizedIndexes(theme.source_segment_indexes)
            if indexes.isEmpty || !Set(indexes).isSubset(of: validSegmentIndexes) {
                issues.append(.invalidThemeSegments)
            }
        }

        var normalizedInstructions = Set<String>()
        for objective in dto.objectives {
            let instruction = mechanicallyNormalized(objective.instruction)
            if instruction.isEmpty { issues.append(.emptyObjective) }
            if instruction.count > 500 { issues.append(.objectiveTooLong) }
            if !normalizedInstructions.insert(textIdentity(instruction)).inserted {
                issues.append(.duplicateObjective)
            }
            guard let theme = themeDTOByID[objective.theme_id] else {
                issues.append(.invalidObjectiveTheme)
                continue
            }
            let objectiveIndexes = normalizedIndexes(objective.source_segment_indexes)
            let themeIndexes = Set(normalizedIndexes(theme.source_segment_indexes))
            if objectiveIndexes.isEmpty ||
                !Set(objectiveIndexes).isSubset(of: validSegmentIndexes) ||
                !Set(objectiveIndexes).isSubset(of: themeIndexes) {
                issues.append(.invalidObjectiveSegments)
            }

            if !allocations.isEmpty {
                guard let allocationIndex = objective.allocation_index,
                      let allocation = allocationByIndex[allocationIndex],
                      Set(objectiveIndexes).isSubset(of: Set(allocation.startIndex...allocation.endIndex)) else {
                    issues.append(.invalidManualDistribution)
                    continue
                }
            }
        }

        if !allocations.isEmpty {
            for (allocationIndex, allocation) in allocationByIndex {
                let actual = dto.objectives.filter { $0.allocation_index == allocationIndex }.count
                if actual != allocation.cardCount { issues.append(.invalidManualDistribution) }
            }
        }

        guard issues.isEmpty else {
            throw AIBlueprintValidationFailure(issues: Array(Set(issues)))
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
