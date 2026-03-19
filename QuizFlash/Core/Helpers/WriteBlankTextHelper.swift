//
//  WriteBlankTextHelper.swift
//  QuizFlash
//
//  Shared anchored-blank validation and rendering for write cards.
//

import Foundation

// MARK: - WriteBlankTextHelper

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
}
