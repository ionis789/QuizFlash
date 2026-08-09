//
//  AISourceAllocationPlanner.swift
//  QuizFlash
//

import Foundation

/// Pure production allocation policy shared by every source-generation entry
/// point. It preserves source coverage while bounding each recoverable batch.
nonisolated enum AISourceAllocationPlanner {
    private static let maximumCardsPerAllocation = 10

    static func automaticAllocations(
        for characterCounts: [Int],
        totalCards: Int
    ) -> [AISourceRangeAllocation] {
        guard !characterCounts.isEmpty, totalCards > 0 else { return [] }

        let coverageRangeCount = preferredCoverageRangeCount(
            itemCount: characterCounts.count,
            totalCards: totalCards
        )
        let baseRanges = weightedCoverageRanges(
            for: characterCounts,
            groupCount: coverageRangeCount
        )
        guard !baseRanges.isEmpty else { return [] }

        let weights = normalizedWeights(from: characterCounts)
        let rangeWeights = baseRanges.map { range in
            weights[range].reduce(0, +)
        }
        let cardCounts = cappedDistributedCardCounts(
            totalCards: totalCards,
            across: rangeWeights,
            maxCardsPerAllocation: maximumCardsPerAllocation
        )
        let allocations: [AISourceRangeAllocation] = zip(baseRanges, cardCounts).compactMap { range, cardCount in
            guard cardCount > 0 else { return nil }
            return AISourceRangeAllocation(
                startIndex: range.lowerBound + 1,
                endIndex: range.upperBound + 1,
                cardCount: cardCount
            )
        }
        return splitLargeAutomaticAllocations(
            allocations,
            characterCounts: characterCounts,
            maxCardsPerAllocation: maximumCardsPerAllocation
        )
    }

    static func distributedCardCounts(
        totalCards: Int,
        across weights: [Double]
    ) -> [Int] {
        guard !weights.isEmpty, totalCards > 0 else { return [] }

        var counts = Array(repeating: 1, count: weights.count)
        let remainingCards = totalCards - counts.count
        guard remainingCards > 0 else { return counts }

        let safeTotalWeight = max(weights.reduce(0, +), .leastNonzeroMagnitude)
        let rawExtras = weights.map { weight in
            (weight / safeTotalWeight) * Double(remainingCards)
        }

        var assignedExtras = 0
        var remainders: [(index: Int, value: Double)] = []
        for (index, rawExtra) in rawExtras.enumerated() {
            let wholeCards = Int(rawExtra.rounded(.down))
            counts[index] += wholeCards
            assignedExtras += wholeCards
            remainders.append((index: index, value: rawExtra - Double(wholeCards)))
        }

        let leftoverCards = remainingCards - assignedExtras
        guard leftoverCards > 0 else { return counts }
        let orderedIndices = remainders
            .sorted {
                if $0.value == $1.value {
                    return weights[$0.index] > weights[$1.index]
                }
                return $0.value > $1.value
            }
            .map(\.index)
        for offset in 0 ..< leftoverCards {
            counts[orderedIndices[offset % orderedIndices.count]] += 1
        }
        return counts
    }

    private static func preferredCoverageRangeCount(
        itemCount: Int,
        totalCards: Int
    ) -> Int {
        guard itemCount > 0, totalCards > 0 else { return 0 }
        if itemCount <= 8 {
            return min(itemCount, totalCards)
        }
        if totalCards >= 91 {
            let highVolumeCardDriven = Int(ceil(Double(totalCards) / 10.0))
            let preferredCount = max(3, highVolumeCardDriven)
            return min(itemCount, min(totalCards, min(preferredCount, 14)))
        }
        let sourceDriven = Int(ceil(Double(itemCount) / 6.0))
        let cardDriven = Int(ceil(Double(totalCards) / 8.0))
        let preferredCount = max(3, max(sourceDriven, cardDriven))
        return min(itemCount, min(totalCards, min(preferredCount, 14)))
    }

    private static func splitLargeAutomaticAllocations(
        _ allocations: [AISourceRangeAllocation],
        characterCounts: [Int],
        maxCardsPerAllocation: Int
    ) -> [AISourceRangeAllocation] {
        let safeLimit = max(maxCardsPerAllocation, 1)
        return allocations.flatMap { allocation -> [AISourceRangeAllocation] in
            guard allocation.cardCount > safeLimit else { return [allocation] }

            let lowerBound = max(allocation.startIndex - 1, 0)
            let upperBound = min(allocation.endIndex, characterCounts.count)
            guard lowerBound < upperBound else {
                return splitAllocationByCardsOnly(allocation, maxCardsPerAllocation: safeLimit)
            }

            let requestedSplitCount = Int(ceil(Double(allocation.cardCount) / Double(safeLimit)))
            let splitCount = min(requestedSplitCount, upperBound - lowerBound)
            guard splitCount > 1 else {
                return splitAllocationByCardsOnly(allocation, maxCardsPerAllocation: safeLimit)
            }

            let localCounts = Array(characterCounts[lowerBound ..< upperBound])
            let localRanges = weightedCoverageRanges(for: localCounts, groupCount: splitCount)
            guard !localRanges.isEmpty else {
                return splitAllocationByCardsOnly(allocation, maxCardsPerAllocation: safeLimit)
            }

            let cardCounts = evenlyDistributedCardCounts(allocation.cardCount, across: localRanges.count)
            return zip(localRanges, cardCounts).map { range, cardCount in
                AISourceRangeAllocation(
                    startIndex: lowerBound + range.lowerBound + 1,
                    endIndex: lowerBound + range.upperBound + 1,
                    cardCount: cardCount
                )
            }
        }
    }

    private static func splitAllocationByCardsOnly(
        _ allocation: AISourceRangeAllocation,
        maxCardsPerAllocation: Int
    ) -> [AISourceRangeAllocation] {
        let splitCount = Int(ceil(Double(allocation.cardCount) / Double(maxCardsPerAllocation)))
        return evenlyDistributedCardCounts(allocation.cardCount, across: splitCount)
            .map { cardCount in
                AISourceRangeAllocation(
                    startIndex: allocation.startIndex,
                    endIndex: allocation.endIndex,
                    cardCount: cardCount
                )
            }
    }

    private static func evenlyDistributedCardCounts(
        _ totalCards: Int,
        across count: Int
    ) -> [Int] {
        guard totalCards > 0, count > 0 else { return [] }
        var result = Array(repeating: totalCards / count, count: count)
        for index in 0 ..< (totalCards % count) {
            result[index] += 1
        }
        return result
    }

    private static func cappedDistributedCardCounts(
        totalCards: Int,
        across weights: [Double],
        maxCardsPerAllocation: Int
    ) -> [Int] {
        let safeLimit = max(maxCardsPerAllocation, 1)
        var counts = distributedCardCounts(totalCards: totalCards, across: weights)
        guard !counts.isEmpty, counts.count * safeLimit >= totalCards else { return counts }
        while let overIndex = counts.firstIndex(where: { $0 > safeLimit }),
              let underIndex = counts.firstIndex(where: { $0 < safeLimit }) {
            counts[overIndex] -= 1
            counts[underIndex] += 1
        }
        return counts
    }

    private static func normalizedWeights(from characterCounts: [Int]) -> [Double] {
        let positiveCounts = characterCounts.filter { $0 > 0 }
        let averagePositive = positiveCounts.isEmpty
            ? 1.0
            : Double(positiveCounts.reduce(0, +)) / Double(positiveCounts.count)
        let floorWeight = max(1.0, averagePositive * 0.18)
        return characterCounts.map { count in
            max(Double(count), floorWeight)
        }
    }

    private static func weightedCoverageRanges(
        for characterCounts: [Int],
        groupCount: Int
    ) -> [ClosedRange<Int>] {
        guard !characterCounts.isEmpty, groupCount > 0 else { return [] }
        let cappedGroupCount = min(groupCount, characterCounts.count)
        let weights = normalizedWeights(from: characterCounts)
        if cappedGroupCount == characterCounts.count {
            return characterCounts.indices.map { $0 ... $0 }
        }

        var ranges: [ClosedRange<Int>] = []
        var startIndex = 0
        for groupIndex in 0 ..< (cappedGroupCount - 1) {
            let groupsRemaining = cappedGroupCount - groupIndex
            let remainingWeight = weights[startIndex...].reduce(0, +)
            let targetWeight = remainingWeight / Double(groupsRemaining)
            let latestEndIndex = characterCounts.count - groupsRemaining

            var endIndex = startIndex
            var accumulatedWeight = 0.0
            while endIndex < latestEndIndex {
                accumulatedWeight += weights[endIndex]
                if accumulatedWeight >= targetWeight { break }
                endIndex += 1
            }
            ranges.append(startIndex ... endIndex)
            startIndex = endIndex + 1
        }
        ranges.append(startIndex ... (characterCounts.count - 1))
        return ranges
    }
}
