import Foundation

// =============================================================================
// MARK: - AIZoneParser
// =============================================================================
//
// Converts GPT text (|||ZONE|||-delimited) into a ZoneModel tree.
// NO recursion — each zone string maps directly to one leaf ZoneModel.
// Heavy LaTeX repair is deferred to MathTextSanitizer.heal() at render time.
//
// =============================================================================

struct AIZoneParser {

    static let zoneDelimiter = "|||ZONE|||"

    // -------------------------------------------------------------------------
    // MARK: - Public API
    // -------------------------------------------------------------------------

    static func parse(text: String) -> ZoneModel {
        let zones = extractZoneStrings(from: text)
        return buildTree(from: zones)
    }

    static func parse(zones: [String]) -> ZoneModel {
        let cleaned = zones
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return buildTree(from: cleaned)
    }

    // -------------------------------------------------------------------------
    // MARK: - Extraction
    // -------------------------------------------------------------------------

    private static func extractZoneStrings(from text: String) -> [String] {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        raw = fixLiteralNewlines(raw)

        raw = raw.replacingOccurrences(of: "\n```", with: "\n\(zoneDelimiter)```")
        raw = raw.replacingOccurrences(of: "```\n", with: "```\(zoneDelimiter)\n")

        let parts = raw.contains(zoneDelimiter)
            ? raw.components(separatedBy: zoneDelimiter)
        : [raw]

        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    // -------------------------------------------------------------------------
    // MARK: - Tree Builder  (NO recursion)
    // -------------------------------------------------------------------------

    private static func buildTree(from zones: [String]) -> ZoneModel {
        switch zones.count {
        case 0: return .empty()
        case 1: return makeLeaf(zones[0])
        default: return .container(direction: .vertical, children: zones.map { makeLeaf($0) })
        }
    }

    private static func makeLeaf(_ content: String) -> ZoneModel {
        let processed = fixLiteralNewlines(content)
        let trimmed = processed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty() }

        // Verificăm dacă zona este un bloc de cod markdown
        if trimmed.hasPrefix("```") && trimmed.hasSuffix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            if lines.count > 1 {
                // Extragem limbajul (ex: java din ```java)
                let firstLine = lines[0].trimmingCharacters(in: CharacterSet(charactersIn: "`").union(.whitespaces))
                let language = firstLine.isEmpty ? nil : firstLine

                // Extragem codul efectiv (fără prima și ultima linie)
                let codeContent = lines.dropFirst().dropLast().joined(separator: "\n")

                return .code(codeContent, language: language)
            }
        }

        return .text(processed)
    }

    // -------------------------------------------------------------------------
    // MARK: - Literal \n Fix
    // -------------------------------------------------------------------------

    /// Replaces backslash-n sequences with real newlines, but only when they
    /// are clearly escaped newlines (followed by whitespace/digit), NOT when
    /// they are the start of a LaTeX command like \nabla or \nu.
    static func fixLiteralNewlines(_ input: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"\\n(?=[ \t\r\d\$\-\*\•]|$)"#
        ) else { return input }
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: "\n")
    }

    // -------------------------------------------------------------------------
    // MARK: - Storage Sanitize (called by AIFlashcardService at import time)
    // -------------------------------------------------------------------------

    /// Light sanitization at import time.
    /// Heavy repair (bare LaTeX, orphan $) happens in MathTextSanitizer.heal().
    static func sanitizeForStorage(_ input: String) -> String {
        var t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        t = fixLiteralNewlines(t)
        t = fixUnbalancedDoubleDollars(t)
        return t
    }

    /// Backwards-compatible alias.
    static func sanitizeLatex(_ input: String) -> String { sanitizeForStorage(input) }

    // -------------------------------------------------------------------------
    // MARK: - Helpers
    // -------------------------------------------------------------------------

    private static func fixUnbalancedDoubleDollars(_ input: String) -> String {
        var count = 0
        var searchRange = input.startIndex..<input.endIndex
        while let range = input.range(of: "$$", range: searchRange) {
            count += 1
            searchRange = range.upperBound..<input.endIndex
        }
        return count % 2 != 0 ? input + "$$" : input
    }
}

// =============================================================================
// MARK: - ZoneModel Convenience
// =============================================================================

extension ZoneModel {
    static func fromAIZones(_ zones: [String]) -> ZoneModel { AIZoneParser.parse(zones: zones) }
    static func fromAIText(_ text: String) -> ZoneModel { AIZoneParser.parse(text: text) }
}
