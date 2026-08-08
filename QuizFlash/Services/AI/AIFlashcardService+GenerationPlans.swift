import Foundation
import UIKit

extension AIFlashcardService {
    // -------------------------------------------------------------------------
    // MARK: - Chunking Helpers
    // -------------------------------------------------------------------------

    func buildTextBatchPlans(
        text: String,
        targetCards: Int,
        options: AIGenerationOptions
    ) -> [TextBatchPlan] {
        let batchSizes = makeCardBatchSizes(
            totalCards: targetCards,
            batchSize: options.resolvedCardsPerBatch(for: targetCards)
        )
        guard !batchSizes.isEmpty else { return [] }

        var units = makeTextUnits(from: text)
        units = expandTextUnits(units, toReach: batchSizes.count)

        let groupedUnits = distributeElementsProportionally(units, weights: batchSizes)

        return groupedUnits.enumerated().compactMap { index, group in
            guard !group.isEmpty else { return nil }

            let content = group
                .map(\.content)
                .joined(separator: DocumentTextExtractor.pageSeparator)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !content.isEmpty else { return nil }

            let passIndex = group.compactMap { unit -> Int? in
                if let start = unit.label.range(of: "(focus pass "),
                   let end = unit.label.range(of: ")", range: start.upperBound..<unit.label.endIndex) {
                    return Int(unit.label[start.upperBound..<end.lowerBound])
                }
                return nil
            }.max() ?? 1

            return TextBatchPlan(
                text: content,
                sourceLabel: group.map(\.label).joined(separator: ", "),
                allocationID: nil,
                targetCards: batchSizes[index],
                batchIndex: index + 1,
                totalBatches: batchSizes.count,
                passIndex: passIndex,
                blueprintContext: nil,
                serializationKey: nil
            )
        }
    }

    func buildVisionBatchPlans(
        images: [UIImage],
        targetCards: Int,
        options: AIGenerationOptions
    ) -> [VisionBatchPlan] {
        let batchSizes = makeCardBatchSizes(
            totalCards: targetCards,
            batchSize: options.resolvedCardsPerBatch(for: targetCards)
        )
        guard !batchSizes.isEmpty else { return [] }

        let units = images.enumerated().map { index, _ in
            TextSourceUnit(content: "", label: "Page \(index + 1)")
        }

        let selectedImages = units.compactMap { unit -> UIImage? in
            guard let pageIndex = Int(unit.label.replacingOccurrences(of: "Page ", with: "")),
                  images.indices.contains(pageIndex - 1) else { return nil }
            return images[pageIndex - 1]
        }
        guard !selectedImages.isEmpty else { return [] }

        let selectedLabels = units.map(\.label)
        let baseGroupCount = min(max(1, selectedImages.count), batchSizes.count)
        let groupedImages = distributeElementsEvenly(selectedImages, into: baseGroupCount)
        let groupedLabels = distributeElementsEvenly(selectedLabels, into: baseGroupCount)

        var plans: [VisionBatchPlan] = []

        for (index, batchSize) in batchSizes.enumerated() {
            let groupIndex = index % baseGroupCount
            let passIndex = (index / baseGroupCount) + 1
            let imagesForBatch = groupedImages[groupIndex]
            guard !imagesForBatch.isEmpty else { continue }

            let sourceLabel = groupedLabels[groupIndex].joined(separator: ", ")
            plans.append(
                VisionBatchPlan(
                    images: imagesForBatch,
                    sourceLabel: sourceLabel,
                    allocationID: nil,
                    targetCards: batchSize,
                    batchIndex: index + 1,
                    totalBatches: batchSizes.count,
                    passIndex: passIndex
                )
            )
        }

        return plans
    }

    func buildTextBatchPlans(
        segments: [AITextSourceSegment],
        allocations: [AISourceRangeAllocation],
        options: AIGenerationOptions
    ) -> [TextBatchPlan] {
        guard !segments.isEmpty else { return [] }

        var plans: [TextBatchPlan] = []
        let deliveryBatchSize = options.resolvedCardsPerBatch(
            for: allocations.reduce(0) { $0 + $1.cardCount }
        )

        for allocation in normalizedAllocations(allocations, segmentCount: segments.count) {
            let selectedSegments = Array(segments[(allocation.startIndex - 1)..<allocation.endIndex])
            let batchSizes = makeCardBatchSizes(
                totalCards: allocation.cardCount,
                batchSize: min(deliveryBatchSize, allocation.cardCount)
            )
            let selectedUnits = selectedSegments.map {
                TextSourceUnit(content: $0.text, label: $0.label)
            }
            let expandedUnits = expandTextUnits(selectedUnits, toReach: batchSizes.count)
            let groupedUnits = distributeElementsProportionally(
                expandedUnits,
                weights: batchSizes
            )
            guard !groupedUnits.isEmpty else { continue }

            for (index, batchSize) in batchSizes.enumerated() {
                let groupIndex = index % groupedUnits.count
                let unitGroup = groupedUnits[groupIndex]
                let text = unitGroup
                    .map(\.content)
                    .joined(separator: DocumentTextExtractor.pageSeparator)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }

                plans.append(
                    TextBatchPlan(
                        text: text,
                        sourceLabel: sourceLabel(for: unitGroup.map(\.label)),
                        allocationID: allocation.id,
                        targetCards: batchSize,
                        batchIndex: 0,
                        totalBatches: 0,
                        passIndex: passIndex(for: unitGroup, fallback: (index / groupedUnits.count) + 1),
                        blueprintContext: nil,
                        serializationKey: nil
                    )
                )
            }
        }

        return indexed(plans)
    }

    func buildBlueprintTextBatchPlans(
        segments: [AITextSourceSegment],
        blueprint: AISourceBlueprint,
        remainingObjectiveIDs: Set<UUID>? = nil,
        options: AIGenerationOptions
    ) -> [TextBatchPlan] {
        let selectedObjectives = remainingObjectiveIDs.map { ids in
            blueprint.objectives.filter { ids.contains($0.id) }
        } ?? blueprint.objectives
        guard !selectedObjectives.isEmpty else { return [] }

        let segmentByIndex = Dictionary(uniqueKeysWithValues: segments.map { ($0.index, $0) })
        let objectiveByTheme = Dictionary(grouping: selectedObjectives, by: \.themeID)
        let globalOutline = blueprint.themes.map { theme in
            let compactSummary = String(theme.summary.prefix(180))
            return "\(theme.title): \(compactSummary)"
        }.joined(separator: "\n")
        let deliveryBatchSize = min(
            options.resolvedCardsPerBatch(for: selectedObjectives.count),
            maxCardsPerBlueprintBatch
        )
        var plans: [TextBatchPlan] = []

        for theme in blueprint.themes {
            guard let objectives = objectiveByTheme[theme.id], !objectives.isEmpty else { continue }
            let groupedByAllocation = Dictionary(grouping: objectives) {
                $0.sourceAllocationID?.uuidString ?? "automatic"
            }
                .values
                .sorted { lhs, rhs in
                    let leftIndex = lhs.first.flatMap { objectives.firstIndex(of: $0) } ?? 0
                    let rightIndex = rhs.first.flatMap { objectives.firstIndex(of: $0) } ?? 0
                    return leftIndex < rightIndex
                }
            for allocationObjectives in groupedByAllocation {
                for start in stride(from: 0, to: allocationObjectives.count, by: deliveryBatchSize) {
                    let batchObjectives = Array(allocationObjectives[start..<min(start + deliveryBatchSize, allocationObjectives.count)])
                    let sourceIndexes = Array(Set(batchObjectives.flatMap(\.sourceSegmentIndexes))).sorted()
                    let localSegments = sourceIndexes.compactMap { segmentByIndex[$0] }
                    let sourceText = localSegments.map { segment in
                        "[SOURCE_SEGMENT index=\(segment.index) label=\(segment.label)]\n\(segment.text)\n[/SOURCE_SEGMENT]"
                    }.joined(separator: "\n\n")
                    guard !sourceText.isEmpty else { continue }

                    plans.append(
                        TextBatchPlan(
                            text: sourceText,
                            sourceLabel: sourceLabel(for: localSegments.map(\.label)),
                            allocationID: batchObjectives.first?.sourceAllocationID,
                            targetCards: batchObjectives.count,
                            batchIndex: 0,
                            totalBatches: 0,
                            passIndex: 1,
                            blueprintContext: AIBlueprintBatchContext(
                                globalOutline: globalOutline,
                                theme: theme,
                                objectives: batchObjectives
                            ),
                            // Exact blueprint objectives are independent. A unique
                            // key keeps recovery splits serialized while allowing
                            // initial batches from the same theme to run in parallel.
                            serializationKey: "\(theme.id.uuidString):\(plans.count)"
                        )
                    )
                }
            }
        }

        return indexed(plans)
    }

    func buildVisionBatchPlans(
        images: [UIImage],
        labels: [String],
        allocations: [AISourceRangeAllocation],
        options: AIGenerationOptions
    ) -> [VisionBatchPlan] {
        guard !images.isEmpty else { return [] }

        let resolvedLabels: [String]
        if labels.count == images.count {
            resolvedLabels = labels
        } else {
            resolvedLabels = images.indices.map { "Page \($0 + 1)" }
        }

        var plans: [VisionBatchPlan] = []
        let deliveryBatchSize = options.resolvedCardsPerBatch(
            for: allocations.reduce(0) { $0 + $1.cardCount }
        )

        for allocation in normalizedAllocations(allocations, segmentCount: images.count) {
            let range = (allocation.startIndex - 1)..<allocation.endIndex
            guard !range.isEmpty else { continue }

            let batchSizes = makeCardBatchSizes(
                totalCards: allocation.cardCount,
                batchSize: min(deliveryBatchSize, allocation.cardCount)
            )
            let groupedImageIndexes = groupedSourceIndexes(
                Array(range),
                batchCount: batchSizes.count
            )
            guard !groupedImageIndexes.isEmpty else { continue }

            for (index, batchSize) in batchSizes.enumerated() {
                let groupIndex = index % groupedImageIndexes.count
                let imageIndexes = groupedImageIndexes[groupIndex]
                let imagesForBatch = imageIndexes.map { images[$0] }
                let labelsForBatch = imageIndexes.map { resolvedLabels[$0] }
                guard !imagesForBatch.isEmpty else { continue }

                plans.append(
                    VisionBatchPlan(
                        images: imagesForBatch,
                        sourceLabel: sourceLabel(for: labelsForBatch),
                        allocationID: allocation.id,
                        targetCards: batchSize,
                        batchIndex: 0,
                        totalBatches: 0,
                        passIndex: (index / groupedImageIndexes.count) + 1
                    )
                )
            }
        }

        return indexed(plans)
    }

    func makeTextUnits(from text: String) -> [TextSourceUnit] {
        let pages = text.components(separatedBy: DocumentTextExtractor.pageSeparator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if pages.count > 1 {
            return pages.enumerated().map { index, page in
                TextSourceUnit(content: page, label: "Page \(index + 1)")
            }
        }

        let chunks = splitBySize(text)
        return chunks.enumerated().map { index, chunk in
            TextSourceUnit(content: chunk, label: "Section \(index + 1)")
        }
    }

    func sampleTextUnitsEvenly(_ units: [TextSourceUnit], limit: Int?) -> [TextSourceUnit] {
        guard let limit, limit > 0, units.count > limit else { return units }
        let indices = evenlySampledIndices(totalCount: units.count, sampleCount: limit)
        return indices.map { units[$0] }
    }

    func expandTextUnits(_ units: [TextSourceUnit], toReach targetCount: Int) -> [TextSourceUnit] {
        guard !units.isEmpty, targetCount > units.count else { return units }

        var expanded = units

        while expanded.count < targetCount {
            guard let longestIndex = expanded.indices.max(by: {
                expanded[$0].content.count < expanded[$1].content.count
            }) else {
                break
            }

            let current = expanded[longestIndex]
            guard let splitUnits = splitTextUnit(current), splitUnits.count > 1 else {
                break
            }

            expanded.remove(at: longestIndex)
            expanded.insert(contentsOf: splitUnits.reversed(), at: longestIndex)
        }

        if expanded.count >= targetCount {
            return expanded
        }

        let baseUnits = expanded
        var passIndex = 2
        var cursor = 0

        while expanded.count < targetCount {
            let base = baseUnits[cursor % baseUnits.count]
            expanded.append(
                TextSourceUnit(
                    content: base.content,
                    label: "\(base.label) (focus pass \(passIndex))"
                )
            )
            cursor += 1
            if cursor % baseUnits.count == 0 {
                passIndex += 1
            }
        }

        return expanded
    }

    func splitTextUnit(_ unit: TextSourceUnit) -> [TextSourceUnit]? {
        let paragraphs = unit.content.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if paragraphs.count >= 2 {
            let splitIndex = max(1, paragraphs.count / 2)
            return [
                TextSourceUnit(content: paragraphs[..<splitIndex].joined(separator: "\n\n"), label: "\(unit.label) A"),
                TextSourceUnit(content: paragraphs[splitIndex...].joined(separator: "\n\n"), label: "\(unit.label) B")
            ]
        }

        let lines = unit.content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.count >= 8 {
            let splitIndex = max(1, lines.count / 2)
            return [
                TextSourceUnit(content: lines[..<splitIndex].joined(separator: "\n"), label: "\(unit.label) A"),
                TextSourceUnit(content: lines[splitIndex...].joined(separator: "\n"), label: "\(unit.label) B")
            ]
        }

        let chunks = splitBySize(unit.content)
        guard chunks.count >= 2 else { return nil }
        return chunks.enumerated().map { index, chunk in
            TextSourceUnit(content: chunk, label: "\(unit.label) \(Character(UnicodeScalar(65 + index)!))")
        }
    }

    func splitBySize(_ text: String) -> [String] {
        var chunks: [String] = []
        var startIndex = text.startIndex
        while startIndex < text.endIndex {
            let endOffset = min(maxCharsPerChunk, text.distance(from: startIndex, to: text.endIndex))
            var endIndex = text.index(startIndex, offsetBy: endOffset)
            if endIndex < text.endIndex {
                let lookback = text[startIndex..<endIndex]
                if let lastBreak = lookback.rangeOfCharacter(from: .newlines, options: .backwards) {
                    endIndex = lastBreak.upperBound
                }
            }
            chunks.append(String(text[startIndex..<endIndex]))
            startIndex = endIndex
        }
        return chunks
    }

    func distributeCards(_ total: Int, across count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var result = Array(repeating: total / count, count: count)
        for i in 0..<(total % count) { result[i] += 1 }
        return result
    }

    func makeCardBatchSizes(totalCards: Int, batchSize: Int) -> [Int] {
        guard totalCards > 0 else { return [] }

        var remaining = totalCards
        var batches: [Int] = []
        let normalizedBatchSize = max(batchSize, 1)

        // Front-load a smaller preview batch for smaller jobs. High-volume
        // runs keep uniform batches so request count and token cost stay easy
        // to compare across trace captures.
        if totalCards < 91, totalCards > normalizedBatchSize, normalizedBatchSize >= 4 {
            let previewBatchSize = min(remaining, min(3, max(2, normalizedBatchSize / 2)))
            batches.append(previewBatchSize)
            remaining -= previewBatchSize
        }

        while remaining > 0 {
            let next = min(normalizedBatchSize, remaining)
            batches.append(next)
            remaining -= next
        }

        return batches
    }

    func evenlySampledIndices(totalCount: Int, sampleCount: Int) -> [Int] {
        guard totalCount > 0 else { return [] }
        guard sampleCount < totalCount else { return Array(0..<totalCount) }

        let stride = Double(totalCount - 1) / Double(max(sampleCount - 1, 1))
        var indices = (0..<sampleCount).map { sampleIndex in
            Int((Double(sampleIndex) * stride).rounded())
        }

        indices = Array(Set(indices)).sorted()

        var nextIndex = 0
        while indices.count < sampleCount, nextIndex < totalCount {
            if !indices.contains(nextIndex) {
                indices.append(nextIndex)
            }
            nextIndex += 1
        }

        return indices.sorted()
    }

    func distributeElementsEvenly<T>(_ elements: [T], into groupCount: Int) -> [[T]] {
        guard groupCount > 0 else { return [] }
        guard !elements.isEmpty else { return Array(repeating: [], count: groupCount) }

        let distribution = distributeCards(elements.count, across: groupCount)
        var cursor = 0

        return distribution.map { groupSize in
            guard groupSize > 0 else { return [] }
            let end = min(cursor + groupSize, elements.count)
            let slice = Array(elements[cursor..<end])
            cursor = end
            return slice
        }
    }

    func distributeElementsProportionally<T>(
        _ elements: [T],
        weights: [Int]
    ) -> [[T]] {
        guard !elements.isEmpty, !weights.isEmpty else { return [] }
        let normalizedWeights = weights.map { max($0, 1) }
        let totalWeight = normalizedWeights.reduce(0, +)
        var groups: [[T]] = []
        var startIndex = 0
        var cumulativeWeight = 0

        for index in normalizedWeights.indices {
            cumulativeWeight += normalizedWeights[index]
            let remainingGroups = normalizedWeights.count - index - 1
            let idealEnd = index == normalizedWeights.indices.last
                ? elements.count
                : Int((Double(cumulativeWeight) / Double(totalWeight) * Double(elements.count)).rounded())
            let minimumEnd = min(elements.count, startIndex + 1)
            let maximumEnd = max(minimumEnd, elements.count - remainingGroups)
            let endIndex = min(max(idealEnd, minimumEnd), maximumEnd)
            groups.append(Array(elements[startIndex..<endIndex]))
            startIndex = endIndex
        }

        return groups
    }

    func groupedSourceSegments(
        _ segments: [AITextSourceSegment],
        batchCount: Int
    ) -> [[AITextSourceSegment]] {
        guard !segments.isEmpty, batchCount > 0 else { return [] }
        let groupCount = min(segments.count, batchCount)
        return distributeElementsEvenly(segments, into: groupCount)
    }

    func groupedTextUnits(
        _ units: [TextSourceUnit],
        batchCount: Int
    ) -> [[TextSourceUnit]] {
        guard !units.isEmpty, batchCount > 0 else { return [] }
        let groupCount = min(units.count, batchCount)
        return distributeElementsEvenly(units, into: groupCount)
    }

    func passIndex(for units: [TextSourceUnit], fallback: Int) -> Int {
        units.compactMap { unit -> Int? in
            if let start = unit.label.range(of: "(focus pass "),
               let end = unit.label.range(of: ")", range: start.upperBound..<unit.label.endIndex) {
                return Int(unit.label[start.upperBound..<end.lowerBound])
            }
            return nil
        }.max() ?? fallback
    }

    func groupedSourceIndexes(
        _ indexes: [Int],
        batchCount: Int
    ) -> [[Int]] {
        guard !indexes.isEmpty, batchCount > 0 else { return [] }
        let groupCount = min(indexes.count, batchCount)
        return distributeElementsEvenly(indexes, into: groupCount)
    }

    func normalizedAllocations(
        _ allocations: [AISourceRangeAllocation],
        segmentCount: Int
    ) -> [AISourceRangeAllocation] {
        guard segmentCount > 0 else { return [] }

        return allocations
            .sorted {
                if $0.startIndex == $1.startIndex {
                    return $0.endIndex < $1.endIndex
                }
                return $0.startIndex < $1.startIndex
            }
            .compactMap { allocation in
                let start = min(max(allocation.startIndex, 1), segmentCount)
                let end = min(max(max(allocation.endIndex, start), 1), segmentCount)
                let cardCount = max(allocation.cardCount, 1)

                return AISourceRangeAllocation(
                    id: allocation.id,
                    startIndex: start,
                    endIndex: end,
                    cardCount: cardCount
                )
            }
    }

    func sourceLabel(for labels: [String]) -> String {
        guard let first = labels.first else { return "Selected source" }
        guard let last = labels.last, last != first else { return first }
        return "\(first) - \(last)"
    }

    func indexed(_ plans: [TextBatchPlan]) -> [TextBatchPlan] {
        let total = plans.count
        return plans.enumerated().map { index, plan in
            TextBatchPlan(
                text: plan.text,
                sourceLabel: plan.sourceLabel,
                allocationID: plan.allocationID,
                targetCards: plan.targetCards,
                batchIndex: index + 1,
                totalBatches: total,
                passIndex: plan.passIndex,
                blueprintContext: plan.blueprintContext,
                serializationKey: plan.serializationKey
            )
        }
    }

    func indexed(_ plans: [VisionBatchPlan]) -> [VisionBatchPlan] {
        let total = plans.count
        return plans.enumerated().map { index, plan in
            VisionBatchPlan(
                images: plan.images,
                sourceLabel: plan.sourceLabel,
                allocationID: plan.allocationID,
                targetCards: plan.targetCards,
                batchIndex: index + 1,
                totalBatches: total,
                passIndex: plan.passIndex
            )
        }
    }
}
