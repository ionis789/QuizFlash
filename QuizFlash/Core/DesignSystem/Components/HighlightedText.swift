//
//  HighlightedText.swift
//  QuizFlash
//
//  A reusable SwiftUI `View` that renders text with highlighted search tokens.
//  Lives in `Core/DesignSystem/Components` — pure UI, no data-layer coupling.
//
//  SWIFT 6 ACTOR ISOLATION FIX
//  ─────────────────────────────────────────────────────────────────────────────
//  In Swift 6, SwiftUI's `Font` and `Color` are `@MainActor`-isolated types.
//  Passing them as parameters into a `Task.detached` block crosses an actor
//  boundary, which the compiler correctly rejects.
//
//  SOLUTION — Separate the work into two stages:
//
//  Stage 1 (background thread, fully Sendable):
//    Pure String operations only. Find the byte ranges of every token match.
//    Returns [Range<String.Index>] — a simple value type, fully Sendable.
//
//  Stage 2 (MainActor, after await):
//    Build AttributedString from the ranges using Font/Color.
//    Zero string-searching here — just attribute application, which is fast.
//
//  This keeps the expensive O(text × tokens) work off the main thread while
//  being 100% Swift 6 compliant.

import SwiftUI

// MARK: - Background Range Finder
// No SwiftUI imports, no actor constraints — freely callable on any thread.

private enum RangeFinder {
    struct TokenMatch: Sendable {
        let lowerOffset: Int   // UTF-16 offset from string start
        let upperOffset: Int
    }

    /// Finds all occurrence ranges of every token in `text`.
    /// Returns an array of offsets that can be safely sent across actor boundaries.
    nonisolated static func findMatches(in text: String, tokens: [String]) -> [TokenMatch] {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var matches: [TokenMatch] = []

        for token in tokens {
            var searchRange = text.startIndex..<text.endIndex
            while searchRange.lowerBound < text.endIndex,
                  let matchRange = text.range(of: token, options: options, range: searchRange) {
                let lo = text.utf16.distance(from: text.startIndex, to: matchRange.lowerBound)
                let hi = text.utf16.distance(from: text.startIndex, to: matchRange.upperBound)
                matches.append(TokenMatch(lowerOffset: lo, upperOffset: hi))

                let next = matchRange.upperBound == matchRange.lowerBound
                    ? text.index(after: matchRange.lowerBound)
                    : matchRange.upperBound
                guard next < text.endIndex else { break }
                searchRange = next..<text.endIndex
            }
        }
        return matches
    }
}

// MARK: - HighlightedText

struct HighlightedText: View {
    let text: String
    let query: String
    var font: Font = .subheadline
    var baseColor: Color = .secondary

    @State private var attributed: AttributedString? = nil

    private var accentColor: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        Group {
            if let attributed {
                Text(attributed)
            } else {
                // Plain text shown instantly. Identical layout geometry —
                // no size jump when highlights are applied.
                Text(text)
                    .font(font)
                    .foregroundStyle(baseColor)
            }
        }
        // Restarts whenever text or query changes; cancels the previous task.
        .task(id: TaskKey(text: text, query: query)) {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                attributed = nil
                return
            }

            // ── Stage 1: background — pure String work, no SwiftUI types ──────
            let capturedText   = text
            let capturedTokens = trimmed
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }

            let matches = await Task.detached(priority: .userInitiated) {
                RangeFinder.findMatches(in: capturedText, tokens: capturedTokens)
            }.value

            guard !Task.isCancelled else { return }

            // ── Stage 2: MainActor — build AttributedString from ranges ────────
            // Font and Color are only touched here, on the MainActor.
            // This work is O(matches) — typically < 20 items — so it's negligible.
            let highlight = accentColor
            let f         = font
            let base      = baseColor

            var result = AttributedString(capturedText)
            result.font           = f
            result.foregroundColor = base

            for match in matches {
                // Convert UTF-16 offsets back to String.Index via AttributedString's
                // UTF-16 view, which is stable and correct for all Unicode.
                let utf16 = capturedText.utf16
                guard let loIdx = utf16.index(utf16.startIndex,
                                               offsetBy: match.lowerOffset,
                                               limitedBy: utf16.endIndex),
                      let hiIdx = utf16.index(utf16.startIndex,
                                               offsetBy: match.upperOffset,
                                               limitedBy: utf16.endIndex),
                      let strLo = loIdx.samePosition(in: capturedText),
                      let strHi = hiIdx.samePosition(in: capturedText),
                      let attrRange = Range(strLo..<strHi, in: result)
                else { continue }

                result[attrRange].backgroundColor = highlight.opacity(0.3)
                result[attrRange].font            = f.weight(.bold)
                result[attrRange].foregroundColor = .primary
            }

            attributed = result
        }
        .onChange(of: query) { _, newQuery in
            if newQuery.isEmpty { attributed = nil }
        }
    }

    private struct TaskKey: Equatable {
        let text: String
        let query: String
    }
}
