import XCTest
@testable import QuizFlash

final class AISourceBlueprintTests: XCTestCase {
    func testPlannerUsesExactlyOneDirectRequestWhenSourceFitsBudget() async throws {
        let recorder = BlueprintRequestRecorder(targetCards: 2)
        let planner = AIBlueprintPlanner(
            service: try makeService(),
            profile: AIBlueprintProviderProfile(
                contextTokenLimit: 10_000,
                directInputTokenBudget: 8_000,
                mapInputTokenBudget: 1_000,
                reduceInputTokenBudget: 2_000,
                maxConcurrentMapRequests: 2
            ),
            providerRequestHandler: { request in
                try await recorder.response(for: request)
            }
        )

        let blueprint = try await planner.build(
            segments: makeSegments(2),
            targetCards: 2,
            options: AIGenerationOptions(),
            manualAllocations: []
        )

        XCTAssertEqual(blueprint.objectives.count, 2)
        let operations = await recorder.operations()
        XCTAssertEqual(operations, ["blueprint_reduce"])
    }

    func testPlannerMapsEverySegmentExactlyOnceBeforeFinalReduce() async throws {
        let recorder = BlueprintRequestRecorder(targetCards: 3)
        let planner = AIBlueprintPlanner(
            service: try makeService(),
            profile: AIBlueprintProviderProfile(
                contextTokenLimit: 10_000,
                directInputTokenBudget: 1,
                mapInputTokenBudget: 3_000,
                reduceInputTokenBudget: 4_000,
                maxConcurrentMapRequests: 2
            ),
            providerRequestHandler: { request in
                try await recorder.response(for: request)
            }
        )
        let segments = (1...3).map { index in
            AITextSourceSegment(
                index: index,
                label: "Segment \(index)",
                text: String(repeating: String(index), count: 3_000)
            )
        }

        let blueprint = try await planner.build(
            segments: segments,
            targetCards: 3,
            options: AIGenerationOptions(),
            manualAllocations: []
        )

        let mapPayload = await recorder.mapPayload()
        let mapOperationCount = await recorder.operationCount("blueprint_map")
        let reduceOperationCount = await recorder.operationCount("blueprint_reduce")
        XCTAssertEqual(blueprint.objectives.count, 3)
        XCTAssertEqual(mapOperationCount, 3)
        XCTAssertEqual(reduceOperationCount, 1)
        for index in 1...3 {
            XCTAssertEqual(mapPayload.components(separatedBy: "\"original_segment_index\":\(index)").count - 1, 1)
        }
    }

    func testPlannerRepairsInvalidBlueprintAndStopsAfterTwoInvalidRepairs() async throws {
        let successfulRecorder = BlueprintRequestRecorder(targetCards: 2, invalidInitialResponse: true)
        let successfulPlanner = AIBlueprintPlanner(
            service: try makeService(),
            providerRequestHandler: { request in
                try await successfulRecorder.response(for: request)
            }
        )
        let repaired = try await successfulPlanner.build(
            segments: makeSegments(1),
            targetCards: 2,
            options: AIGenerationOptions(),
            manualAllocations: []
        )
        XCTAssertEqual(repaired.objectives.count, 2)
        let successfulRepairCount = await successfulRecorder.operationCount("blueprint_repair")
        XCTAssertEqual(successfulRepairCount, 1)
        let repairPayload = await successfulRecorder.payload(for: "blueprint_repair")
        XCTAssertTrue(repairPayload.contains("schema=1"))
        XCTAssertTrue(repairPayload.contains("expected_integer\":2"))
        XCTAssertTrue(repairPayload.contains("actual_integer\":1"))

        let failingRecorder = BlueprintRequestRecorder(
            targetCards: 2,
            invalidInitialResponse: true,
            keepRepairsInvalid: true
        )
        let failingPlanner = AIBlueprintPlanner(
            service: try makeService(),
            providerRequestHandler: { request in
                try await failingRecorder.response(for: request)
            }
        )
        do {
            _ = try await failingPlanner.build(
                segments: makeSegments(1),
                targetCards: 2,
                options: AIGenerationOptions(),
                manualAllocations: []
            )
            XCTFail("Expected invalid blueprint failure")
        } catch {
            let failingRepairCount = await failingRecorder.operationCount("blueprint_repair")
            XCTAssertEqual(failingRepairCount, 2)
            let failingRepairPayload = await failingRecorder.payload(for: "blueprint_repair")
            XCTAssertTrue(failingRepairPayload.contains("unchanged_candidate"))
        }
    }

    func testPlannerTrimsValidObjectiveSurplusWithoutRepairRequest() async throws {
        let recorder = BlueprintRequestRecorder(
            targetCards: 3,
            initialObjectiveSurplus: 2,
            themeCount: 2
        )
        let planner = AIBlueprintPlanner(
            service: try makeService(),
            providerRequestHandler: { request in
                try await recorder.response(for: request)
            }
        )

        let blueprint = try await planner.build(
            segments: makeSegments(1),
            targetCards: 3,
            options: AIGenerationOptions(),
            manualAllocations: []
        )

        XCTAssertEqual(blueprint.objectives.count, 3)
        XCTAssertEqual(Set(blueprint.objectives.map(\.themeID)), Set(blueprint.themes.map(\.id)))
        XCTAssertEqual(Set(blueprint.objectives.map(\.instruction)), ["Objective 1", "Objective 4", "Objective 5"])
        let repairCount = await recorder.operationCount("blueprint_repair")
        XCTAssertEqual(repairCount, 0)
    }

    func testPlannerRepairsAnExactCountBlueprintWithAnUncoveredTheme() async throws {
        let recorder = BlueprintRequestRecorder(
            targetCards: 3,
            themeCount: 2,
            initialResponseLeavesThemeUncovered: true
        )
        let planner = AIBlueprintPlanner(
            service: try makeService(),
            providerRequestHandler: { request in
                try await recorder.response(for: request)
            }
        )

        let blueprint = try await planner.build(
            segments: makeSegments(1),
            targetCards: 3,
            options: AIGenerationOptions(),
            manualAllocations: []
        )

        XCTAssertEqual(Set(blueprint.objectives.map(\.themeID)), Set(blueprint.themes.map(\.id)))
        let repairCount = await recorder.operationCount("blueprint_repair")
        XCTAssertEqual(repairCount, 1)
        let repairPayload = await recorder.payload(for: "blueprint_repair")
        XCTAssertTrue(repairPayload.contains("theme_without_objective"))
        XCTAssertTrue(repairPayload.contains("themes[id=2].objectives"))
    }

    func testValidBlueprintProducesExactInternalObjectivesAndNormalizesFields() throws {
        let segments = makeSegments(2)
        let dto = makeDTO(targetCards: 3, segmentIndexes: [1, 2])

        let blueprint = try AIBlueprintValidator.validate(
            dto,
            segments: segments,
            targetCards: 3,
            allocations: [],
            promptVersion: "version",
            sourceFingerprint: "fingerprint"
        )

        XCTAssertEqual(blueprint.objectives.count, 3)
        XCTAssertEqual(blueprint.themes.count, 1)
        XCTAssertEqual(Set(blueprint.objectives.map(\.id)).count, 3)
        XCTAssertTrue(blueprint.objectives.allSatisfy { $0.themeID == blueprint.themes[0].id })
        XCTAssertEqual(blueprint.suggestedTitle, "Source title")
    }

    func testInvalidObjectiveCountRequiresSemanticRepair() {
        assertValidationIssue(.wrongObjectiveCount(expected: 3, actual: 2)) {
            try validate(makeDTO(targetCards: 2), targetCards: 3)
        }
    }

    func testThemeWithoutObjectiveRequiresSemanticRepair() {
        let dto = AIBlueprintResponseDTO(
            schema_version: 1,
            suggested_title: "Source title",
            language_code: "aa",
            language_display_name: "Detected language",
            themes: [
                .init(id: 1, title: "Theme 1", summary: "Summary 1", source_segment_indexes: [1], relative_priority: 1),
                .init(id: 2, title: "Theme 2", summary: "Summary 2", source_segment_indexes: [1], relative_priority: 2)
            ],
            objectives: [
                .init(id: 1, theme_id: 1, instruction: "Objective 1", source_segment_indexes: [1], relative_priority: 1, allocation_index: nil),
                .init(id: 2, theme_id: 1, instruction: "Objective 2", source_segment_indexes: [1], relative_priority: 2, allocation_index: nil)
            ]
        )

        XCTAssertThrowsError(try validate(dto, targetCards: 2)) { error in
            guard let failure = error as? AIBlueprintValidationFailure else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(failure.issues.contains(.themeWithoutObjective))
            XCTAssertTrue(failure.repairDiagnostics.contains(.init(
                code: "theme_without_objective",
                path: "themes[id=2].objectives",
                entityID: 2,
                minimumInteger: 1,
                actualInteger: 0
            )))
        }
    }

    func testUncoveredThemeSegmentsRequireSemanticRepair() {
        let dto = AIBlueprintResponseDTO(
            schema_version: 1,
            suggested_title: "Source title",
            language_code: "aa",
            language_display_name: "Detected language",
            themes: [
                .init(id: 1, title: "Theme", summary: "Summary", source_segment_indexes: [1, 2], relative_priority: 1)
            ],
            objectives: [
                .init(id: 1, theme_id: 1, instruction: "Objective", source_segment_indexes: [1], relative_priority: 1, allocation_index: nil)
            ]
        )

        XCTAssertThrowsError(try validate(dto, targetCards: 1)) { error in
            guard let failure = error as? AIBlueprintValidationFailure else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(failure.issues.contains(.uncoveredThemeSegments))
            XCTAssertTrue(failure.repairDiagnostics.contains(.init(
                code: "uncovered_theme_segments",
                path: "themes[id=1].source_segment_indexes",
                entityID: 1,
                expectedIndexes: [1, 2],
                actualIndexes: [1]
            )))
        }
    }

    func testDuplicateObjectiveTextRequiresSemanticRepairAfterUnicodeNormalization() {
        var dto = makeDTO(targetCards: 2)
        dto = AIBlueprintResponseDTO(
            schema_version: dto.schema_version,
            suggested_title: dto.suggested_title,
            language_code: dto.language_code,
            language_display_name: dto.language_display_name,
            themes: dto.themes,
            objectives: [
                .init(id: 1, theme_id: 1, instruction: "Atomic objective", source_segment_indexes: [1], relative_priority: 1, allocation_index: nil),
                .init(id: 2, theme_id: 1, instruction: "  atomic   OBJECTIVE  ", source_segment_indexes: [1], relative_priority: 1, allocation_index: nil)
            ]
        )

        assertValidationIssue(.duplicateObjective) {
            try validate(dto, targetCards: 2)
        }
    }

    func testInvalidSegmentReferenceRequiresSemanticRepair() {
        let dto = makeDTO(targetCards: 1, segmentIndexes: [9])
        assertValidationIssue(.invalidThemeSegments) {
            try validate(dto, targetCards: 1)
        }
    }

    func testValidationFailureIdentifiesExactSchemaAndObjectiveSegmentRepairs() {
        let dto = AIBlueprintResponseDTO(
            schema_version: 5,
            suggested_title: "Source title",
            language_code: "aa",
            language_display_name: "Detected language",
            themes: [
                .init(id: 1, title: "Theme", summary: "Summary", source_segment_indexes: [1], relative_priority: 1)
            ],
            objectives: [
                .init(id: 8, theme_id: 1, instruction: "Objective", source_segment_indexes: [2], relative_priority: 1, allocation_index: nil)
            ]
        )

        XCTAssertThrowsError(try validate(dto, targetCards: 1)) { error in
            guard let failure = error as? AIBlueprintValidationFailure else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(failure.repairDiagnostics.contains(.init(
                code: "unsupported_schema",
                path: "schema_version",
                expectedInteger: 1,
                actualInteger: 5
            )))
            XCTAssertTrue(failure.repairDiagnostics.contains(.init(
                code: "invalid_objective_segments",
                path: "objectives[id=8].source_segment_indexes",
                entityID: 8,
                relatedEntityID: 1,
                expectedIndexes: [1],
                actualIndexes: [2]
            )))
        }
    }

    func testManualDistributionIsExactAndAuthoritative() throws {
        let allocations = [
            AISourceRangeAllocation(startIndex: 1, endIndex: 1, cardCount: 1),
            AISourceRangeAllocation(startIndex: 2, endIndex: 2, cardCount: 2)
        ]
        let objectives: [AIBlueprintResponseDTO.Objective] = [
            .init(id: 1, theme_id: 1, instruction: "Objective 1", source_segment_indexes: [1], relative_priority: 3, allocation_index: 1),
            .init(id: 2, theme_id: 1, instruction: "Objective 2", source_segment_indexes: [2], relative_priority: 2, allocation_index: 2),
            .init(id: 3, theme_id: 1, instruction: "Objective 3", source_segment_indexes: [2], relative_priority: 1, allocation_index: 2)
        ]
        let dto = AIBlueprintResponseDTO(
            schema_version: 1,
            suggested_title: "Source title",
            language_code: "aa",
            language_display_name: "Detected language",
            themes: [.init(id: 1, title: "Theme", summary: "Summary", source_segment_indexes: [1, 2], relative_priority: 1)],
            objectives: objectives
        )

        let blueprint = try AIBlueprintValidator.validate(
            dto,
            segments: makeSegments(2),
            targetCards: 3,
            allocations: allocations,
            promptVersion: "version",
            sourceFingerprint: "fingerprint"
        )

        XCTAssertEqual(blueprint.objectives.filter { $0.sourceAllocationID == allocations[0].id }.count, 1)
        XCTAssertEqual(blueprint.objectives.filter { $0.sourceAllocationID == allocations[1].id }.count, 2)
    }

    func testManualDistributionRejectsCrossRangeObjective() {
        let allocation = AISourceRangeAllocation(startIndex: 1, endIndex: 1, cardCount: 1)
        var dto = makeDTO(targetCards: 1, segmentIndexes: [1, 2])
        dto = AIBlueprintResponseDTO(
            schema_version: dto.schema_version,
            suggested_title: dto.suggested_title,
            language_code: dto.language_code,
            language_display_name: dto.language_display_name,
            themes: dto.themes,
            objectives: [.init(id: 1, theme_id: 1, instruction: "Objective", source_segment_indexes: [2], relative_priority: 1, allocation_index: 1)]
        )
        assertValidationIssue(.invalidManualDistribution) {
            try AIBlueprintValidator.validate(
                dto,
                segments: makeSegments(2),
                targetCards: 1,
                allocations: [allocation],
                promptVersion: "version",
                sourceFingerprint: "fingerprint"
            )
        }
    }

    func testFingerprintIsStableAndChangesWithSourceContent() {
        let original = makeSegments(2)
        let same = makeSegments(2)
        var changed = makeSegments(2)
        changed[1] = AITextSourceSegment(index: 2, label: "Segment 2", text: "Changed source")

        XCTAssertEqual(
            AIBlueprintValidator.sourceFingerprint(for: original),
            AIBlueprintValidator.sourceFingerprint(for: same)
        )
        XCTAssertNotEqual(
            AIBlueprintValidator.sourceFingerprint(for: original),
            AIBlueprintValidator.sourceFingerprint(for: changed)
        )
    }

    func testBlueprintPlansUseSmallIndependentBatchesAcrossThemes() async throws {
        let service = try makeService()
        let segments = makeSegments(2)
        let themeA = AIBlueprintTheme(id: UUID(), title: "Theme A", summary: "Summary A", sourceSegmentIndexes: [1], relativePriority: 2)
        let themeB = AIBlueprintTheme(id: UUID(), title: "Theme B", summary: "Summary B", sourceSegmentIndexes: [2], relativePriority: 1)
        let objectives = (0..<14).map { index in
            let theme = index < 13 ? themeA : themeB
            return AIBlueprintObjective(
                id: UUID(),
                themeID: theme.id,
                instruction: "Objective \(index)",
                sourceSegmentIndexes: theme.sourceSegmentIndexes,
                relativePriority: 14 - index,
                sourceAllocationID: nil
            )
        }
        let blueprint = AISourceBlueprint(
            schemaVersion: 1,
            promptVersion: "version",
            sourceFingerprint: "fingerprint",
            suggestedTitle: "Title",
            dominantLanguage: nil,
            themes: [themeA, themeB],
            objectives: objectives
        )

        let plans = service.buildBlueprintTextBatchPlans(
            segments: segments,
            blueprint: blueprint,
            options: AIGenerationOptions()
        )

        XCTAssertEqual(plans.reduce(0) { $0 + $1.targetCards }, 14)
        XCTAssertEqual(plans.map(\.targetCards).sorted(), [1, 1, 6, 6])
        XCTAssertEqual(Set(plans.compactMap(\.serializationKey)).count, plans.count)
        XCTAssertTrue(plans.allSatisfy { $0.targetCards <= service.maxCardsPerBlueprintBatch })
        XCTAssertEqual(service.effectiveMaxConcurrentRequestCount(for: plans, requestedMaxConcurrent: 6), plans.count)
        await Task.yield()
    }

    func testBlueprintPromptRendersWithoutUnresolvedPlaceholders() async throws {
        let service = try makeService()
        let messages = try service.buildBlueprintDirectMessages(
            sourceJSON: "[]",
            allocationJSON: "[]",
            targetCards: 4,
            options: AIGenerationOptions(),
            sourceFingerprint: "fingerprint",
            promptVersion: "version"
        )
        let rendered = messages.compactMap { $0["content"] as? String }.joined()
        XCTAssertFalse(rendered.contains("{{"))
        XCTAssertTrue(rendered.contains("target=4"))
        XCTAssertTrue(rendered.contains("schema=1"))
        await Task.yield()
    }

    private func validate(
        _ dto: AIBlueprintResponseDTO,
        targetCards: Int
    ) throws -> AISourceBlueprint {
        try AIBlueprintValidator.validate(
            dto,
            segments: makeSegments(2),
            targetCards: targetCards,
            allocations: [],
            promptVersion: "version",
            sourceFingerprint: "fingerprint"
        )
    }

    private func makeService() throws -> AIFlashcardService {
        AIFlashcardService(
            provider: AIProviderProfile(
                name: "Test Provider",
                endpointURLString: "https://example.invalid/v1",
                apiKey: "test",
                textModel: "test-text",
                visionModel: "test-vision"
            ),
            promptBundle: try AIPromptBundleFixture.bundle()
        )
    }

    private func assertValidationIssue(
        _ expectedIssue: AIBlueprintValidationIssue,
        operation: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            guard let failure = error as? AIBlueprintValidationFailure else {
                return XCTFail("Unexpected error: \(error)", file: file, line: line)
            }
            XCTAssertTrue(failure.issues.contains(expectedIssue), file: file, line: line)
        }
    }

    private func makeSegments(_ count: Int) -> [AITextSourceSegment] {
        (1...count).map { index in
            AITextSourceSegment(index: index, label: "Segment \(index)", text: "Source content \(index)")
        }
    }

    private func makeDTO(
        targetCards: Int,
        segmentIndexes: [Int] = [1]
    ) -> AIBlueprintResponseDTO {
        AIBlueprintResponseDTO(
            schema_version: 1,
            suggested_title: "  Source   title  ",
            language_code: "aa",
            language_display_name: "Detected language",
            themes: [
                .init(
                    id: 1,
                    title: "Theme",
                    summary: "Summary",
                    source_segment_indexes: segmentIndexes,
                    relative_priority: 1
                )
            ],
            objectives: (1...targetCards).map { index in
                let segmentIndex = segmentIndexes[(index - 1) % segmentIndexes.count]
                return .init(
                    id: index,
                    theme_id: 1,
                    instruction: "Objective \(index)",
                    source_segment_indexes: [segmentIndex],
                    relative_priority: targetCards - index + 1,
                    allocation_index: nil
                )
            }
        )
    }
}

private actor BlueprintRequestRecorder {
    private let targetCards: Int
    private let invalidInitialResponse: Bool
    private let keepRepairsInvalid: Bool
    private let initialObjectiveSurplus: Int
    private let themeCount: Int
    private let initialResponseLeavesThemeUncovered: Bool
    private var recordedRequests: [AIBlueprintProviderRequest] = []

    init(
        targetCards: Int,
        invalidInitialResponse: Bool = false,
        keepRepairsInvalid: Bool = false,
        initialObjectiveSurplus: Int = 0,
        themeCount: Int = 1,
        initialResponseLeavesThemeUncovered: Bool = false
    ) {
        self.targetCards = targetCards
        self.invalidInitialResponse = invalidInitialResponse
        self.keepRepairsInvalid = keepRepairsInvalid
        self.initialObjectiveSurplus = max(initialObjectiveSurplus, 0)
        self.themeCount = max(themeCount, 1)
        self.initialResponseLeavesThemeUncovered = initialResponseLeavesThemeUncovered
    }

    func response(for request: AIBlueprintProviderRequest) throws -> String {
        recordedRequests.append(request)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        if request.operation == "blueprint_map" {
            let content = request.messages.compactMap { $0["content"] as? String }.joined()
            let indexes = sourceIndexes(in: content)
            let digest = AIBlueprintMapDigest(
                themes: indexes.map {
                    .init(title: "Theme \($0)", summary: "Summary \($0)", source_segment_indexes: [$0], relative_priority: 1)
                },
                objectives: indexes.map {
                    .init(instruction: "Objective \($0)", source_segment_indexes: [$0], relative_priority: 1)
                }
            )
            return String(decoding: try encoder.encode(digest), as: UTF8.self)
        }

        let shouldReturnInvalid: Bool
        if request.operation == "blueprint_reduce" {
            shouldReturnInvalid = invalidInitialResponse &&
                recordedRequests.filter { $0.operation == "blueprint_reduce" }.count == 1
        } else {
            shouldReturnInvalid = request.operation == "blueprint_repair" && keepRepairsInvalid
        }
        let isInitialReduce = request.operation == "blueprint_reduce" &&
            recordedRequests.filter { $0.operation == "blueprint_reduce" }.count == 1
        let objectiveCount = shouldReturnInvalid
            ? max(targetCards - 1, 0)
            : targetCards + (isInitialReduce ? initialObjectiveSurplus : 0)
        let dto = AIBlueprintResponseDTO(
            schema_version: 1,
            suggested_title: "Source title",
            language_code: "aa",
            language_display_name: "Detected language",
            themes: (1...min(themeCount, max(objectiveCount, 1))).map { themeIndex in
                .init(
                    id: themeIndex,
                    title: "Theme \(themeIndex)",
                    summary: "Summary \(themeIndex)",
                    source_segment_indexes: [1],
                    relative_priority: themeCount - themeIndex + 1
                )
            },
            objectives: (0..<objectiveCount).map { index in
                let reservedThemeCount = min(max(themeCount - 1, 0), objectiveCount)
                let reservedThemeStart = objectiveCount - reservedThemeCount
                let themeID: Int
                if isInitialReduce && initialResponseLeavesThemeUncovered {
                    themeID = 1
                } else {
                    themeID = index >= reservedThemeStart
                        ? index - reservedThemeStart + 2
                        : 1
                }
                return .init(
                    id: index + 1,
                    theme_id: themeID,
                    instruction: "Objective \(index + 1)",
                    source_segment_indexes: [1],
                    relative_priority: objectiveCount - index,
                    allocation_index: nil
                )
            }
        )
        return String(decoding: try encoder.encode(dto), as: UTF8.self)
    }

    func operations() -> [String] {
        recordedRequests.map(\.operation)
    }

    func operationCount(_ operation: String) -> Int {
        recordedRequests.filter { $0.operation == operation }.count
    }

    func mapPayload() -> String {
        recordedRequests
            .filter { $0.operation == "blueprint_map" }
            .flatMap(\.messages)
            .compactMap { $0["content"] as? String }
            .joined(separator: "\n")
    }

    func payload(for operation: String) -> String {
        recordedRequests
            .filter { $0.operation == operation }
            .flatMap(\.messages)
            .compactMap { $0["content"] as? String }
            .joined(separator: "\n")
    }

    private func sourceIndexes(in content: String) -> [Int] {
        let pattern = #"\"original_segment_index\":(\d+)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [1] }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        let indexes = expression.matches(in: content, range: range).compactMap { match -> Int? in
            guard let swiftRange = Range(match.range(at: 1), in: content) else { return nil }
            return Int(content[swiftRange])
        }
        return indexes.isEmpty ? [1] : Array(Set(indexes)).sorted()
    }
}
