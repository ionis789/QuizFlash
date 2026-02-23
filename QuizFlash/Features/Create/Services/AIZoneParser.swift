import Foundation

// =============================================================================
// MARK: - AIZoneParser
// =============================================================================
//
// Converts AI text (|||ZONE|||-delimited) into a ZoneModel tree.
// Each zone string maps directly to one leaf ZoneModel.
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

    /// Full normalization pipeline — called on every zone string after JSON decode.
    ///
    /// Layer order matters:
    ///   1. Fix GPT over-escaping (\\lambda → \lambda) — must run FIRST,
    ///      before fixLiteralNewlines so we don't confuse \\n with \n.
    ///   2. Fix literal \n sequences → real newlines.
    ///   3. Fix unbalanced $$ delimiters.
    static func sanitizeForStorage(_ input: String) -> String {
        var t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        t = fixOverescapedLatex(t)   // ← NEW: handles GPT double-backslash hallucination
        t = fixLiteralNewlines(t)
        t = fixUnbalancedDoubleDollars(t)
        return t
    }

    /// Backwards-compatible alias.
    static func sanitizeLatex(_ input: String) -> String { sanitizeForStorage(input) }

    // -------------------------------------------------------------------------
    // MARK: - Over-escaping Fix  (post JSON-decode)
    // -------------------------------------------------------------------------

    /// GPT frequently produces "\\\\lambda" in its JSON output, which after
    /// JSONDecoder becomes "\\lambda" in the Swift String — two backslashes.
    /// KaTeX then sees `\\` (a LaTeX line-break command) followed by `lambda`
    /// as plain text, rendering nothing useful.
    ///
    /// This function fixes that: \\command → \command, \\{ → \{, \\} → \}
    ///
    /// Safe cases we do NOT touch:
    ///   • \\\\ (four chars = two LaTeX newlines, rare inside $…$ but valid)
    ///   • A lone \\ followed by whitespace or end-of-string (LaTeX line break)
    ///
    /// Must be called AFTER JSONDecoder, i.e. on the already-decoded Swift String.
    static func fixOverescapedLatex(_ input: String) -> String {
        // Match: exactly two backslashes followed by a LaTeX-significant char
        // (letter, {, }, |, comma, semicolon, backslash again only if it would
        //  create a triple — we stop at \\\\).
        //
        // Negative lookbehind (?<!\\) ensures we don't collapse \\\\ → \\\\  twice.
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<!\\)\\\\([a-zA-Z\{\}\|\,\;\.\!\(\)\[\]])"#
        ) else { return input }

        let range = NSRange(input.startIndex..., in: input)
        var result = regex.stringByReplacingMatches(
            in: input,
            range: range,
            withTemplate: #"\\$1"#
        )

        // Second pass: catch any residual quadruple-backslash sequences
        // (\\\\command) that survived because the first char was also a backslash.
        // e.g. \\\\frac  →  after pass 1 still \\frac if lookbehind fired → pass 2 fixes.
        if result.contains("\\\\") {
            if let regex2 = try? NSRegularExpression(
                pattern: #"\\\\([a-zA-Z\{\}\|\,\;\.\!\(\)\[\]])"#
            ) {
                let r2 = NSRange(result.startIndex..., in: result)
                result = regex2.stringByReplacingMatches(in: result, range: r2, withTemplate: #"\\$1"#)
            }
        }

        return result
    }

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
