//
//  WriteBlankTextHelper.swift
//  QuizFlash
//
//  Shared anchored-blank validation and rendering for write cards.
//

import Foundation

// MARK: - WriteBlankTextHelper

/// One validated source-text split used to render a write blank inline.
struct WriteInlinePromptSegments: Equatable, Sendable {
    let prefixText: String
    let omittedText: String
    let suffixText: String
}

/// Shared helper for validating and rendering write-card blanks from anchored UTF-16 ranges.
enum WriteBlankTextHelper {

    // MARK: - Validation

    /// Normalizes a persisted source zone into the plain text surface used by write-mode editing and runtime rendering.
    /// - Parameter zone: The persisted write-card source zone.
    /// - Returns: A text string suitable for blank validation and prompt rendering.
    nonisolated static func normalizedSourceText(from zone: ZoneModel) -> String {
        if zone.isLeaf {
            return zone.text
        }

        let preview = zone.previewText(maxLength: 4_000)
        return preview == "Empty" ? "" : preview
    }

    /// Validates a stored blank selection against the current source text.
    /// - Parameters:
    ///   - blankSelection: The stored write-card blank selection.
    ///   - text: The current source text.
    ///   - fallbackZoneID: The zone identifier that should own the restored blank.
    /// - Returns: A validated blank selection, or `nil` when the anchor no longer matches the text.
    nonisolated static func validatedBlankSelection(
        _ blankSelection: WriteBlankSelection,
        in text: String,
        fallbackZoneID: UUID
    ) -> WriteBlankSelection? {
        guard !blankSelection.omittedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let nsRange = nsRange(for: blankSelection)
        guard let stringRange = Range(nsRange, in: text),
              String(text[stringRange]) == blankSelection.omittedText else {
            return nil
        }

        return WriteBlankSelection(
            zoneID: fallbackZoneID,
            utf16Range: blankSelection.utf16Range,
            omittedText: blankSelection.omittedText
        )
    }

    // MARK: - Rendering

    /// Applies the blank marker to the source text when the stored anchor is still valid.
    /// - Parameters:
    ///   - blankSelection: The anchored blank selection to apply.
    ///   - text: The source text that should host the blank.
    /// - Returns: The rendered prompt string with a blank marker, or `nil` when the anchor is invalid.
    nonisolated static func applyingBlank(_ blankSelection: WriteBlankSelection, to text: String) -> String? {
        let nsRange = nsRange(for: blankSelection)
        guard let stringRange = Range(nsRange, in: text),
              String(text[stringRange]) == blankSelection.omittedText else {
            return nil
        }

        var blankedText = text
        blankedText.replaceSubrange(stringRange, with: "____")
        return blankedText
    }

    /// Splits the host text around the validated blank so UI can reveal the answer inline.
    /// - Parameters:
    ///   - blankSelection: The anchored blank selection to apply.
    ///   - text: The source text that should host the blank.
    /// - Returns: Prefix / blank / suffix segments when the anchor is still valid, or `nil`.
    nonisolated static func inlinePromptSegments(
        for blankSelection: WriteBlankSelection,
        in text: String
    ) -> WriteInlinePromptSegments? {
        let nsRange = nsRange(for: blankSelection)
        guard let stringRange = Range(nsRange, in: text),
              String(text[stringRange]) == blankSelection.omittedText else {
            return nil
        }

        return WriteInlinePromptSegments(
            prefixText: String(text[..<stringRange.lowerBound]),
            omittedText: blankSelection.omittedText,
            suffixText: String(text[stringRange.upperBound...])
        )
    }

    /// Renders a validated blanked prompt directly from persisted write-card content.
    /// - Parameter content: The persisted write-card content.
    /// - Returns: A blanked prompt string when the anchor is valid, or `nil`.
    nonisolated static func blankedPrompt(for content: WriteCardContent) -> String? {
        let sourceText = normalizedSourceText(from: content.sourceZone)
        guard let validatedSelection = validatedBlankSelection(
            content.blankSelection,
            in: sourceText,
            fallbackZoneID: content.sourceZone.id
        ) else {
            return nil
        }

        return applyingBlank(validatedSelection, to: sourceText)
    }

    /// Detects whether a write answer is formula-heavy enough to benefit from the assisted builder.
    /// - Parameters:
    ///   - answer: The omitted text stored for the prompt.
    ///   - sourceText: The original source text hosting the blank.
    /// - Returns: `true` when the answer is symbol-dense or LaTeX-like.
    nonisolated static func isFormulaHeavy(answer: String, sourceText: String) -> Bool {
        let combined = answer + " " + sourceText
        let symbolCharacters = CharacterSet(charactersIn: "=+-*/^_<>≤≥≠∑∫√\\{}[]()")
        let symbolMatches = combined.unicodeScalars.filter { symbolCharacters.contains($0) }.count
        let answerSymbolMatches = answer.unicodeScalars.filter { symbolCharacters.contains($0) }.count
        let digitMatches = combined.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        let latinWordMatches = combined
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 2 }
            .count
        let answerWordMatches = answer
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 2 }
            .count
        let hasLatexMarkers = combined.contains("\\") || combined.contains("^{") || combined.contains("_{")
        let nonWhitespaceScalars = combined.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }
        let operatorDensity = nonWhitespaceScalars.isEmpty
            ? 0
            : Double(symbolMatches) / Double(nonWhitespaceScalars.count)

        if hasLatexMarkers { return true }
        if symbolMatches >= 4 && latinWordMatches <= 3 { return true }
        if digitMatches >= 3 && symbolMatches >= 2 { return true }
        if answerSymbolMatches >= 3 && answerWordMatches <= 3 { return true }
        if operatorDensity >= 0.18 && latinWordMatches <= 6 { return true }
        return false
    }

    /// Splits the canonical answer into builder-friendly segments while preserving exact ordering.
    /// - Parameter answer: The stored omitted text.
    /// - Returns: A best-effort ordered segment list for the assisted builder UI.
    nonisolated static func assistedBuilderSegments(for answer: String) -> [String] {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var segments: [String] = []
        var current = ""
        var currentKind: SegmentKind?

        for character in trimmed {
            let nextKind = SegmentKind(character: character)

            if let currentKind, currentKind == nextKind {
                current.append(character)
            } else {
                if !current.isEmpty {
                    segments.append(current)
                }
                current = String(character)
                currentKind = nextKind
            }
        }

        if !current.isEmpty {
            segments.append(current)
        }

        return segments
            .map { $0.replacingOccurrences(of: "\t", with: " ") }
            .filter { !$0.isEmpty }
    }

    // MARK: - Helpers

    /// Converts a persisted UTF-16 range into `NSRange`.
    /// - Parameter blankSelection: The anchored blank selection.
    /// - Returns: The bridged Foundation range.
    nonisolated static func nsRange(for blankSelection: WriteBlankSelection) -> NSRange {
        NSRange(
            location: blankSelection.utf16Range.lowerBound,
            length: blankSelection.utf16Range.count
        )
    }

    /// Lightweight grouping used by the builder tokenizer.
    private nonisolated enum SegmentKind: Equatable {
        case whitespace
        case word
        case digit
        case symbol

        init(character: Character) {
            if character.isWhitespace {
                self = .whitespace
            } else if character.isNumber {
                self = .digit
            } else if character.isLetter {
                self = .word
            } else {
                self = .symbol
            }
        }
    }
}
