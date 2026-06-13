//
//  MathTextSanitizer.swift
//  QuizFlash
//
//  Shared math and inline-code preview normalizer used by both live WebKit
//  renderers and lightweight card-grid fallbacks.
//

import Foundation

// =============================================================================
// MARK: - MathTextSanitizer
// =============================================================================

struct MathTextSanitizer {

    // -------------------------------------------------------------------------
    // MARK: - Constants
    // -------------------------------------------------------------------------

    /// Known LaTeX math function names — these are NOT natural-language words.
    nonisolated static let mathFunctionNames: Set<String> = [
        "sin", "cos", "tan", "cot", "sec", "csc", "log", "ln", "exp",
        "lim", "limsup", "liminf", "sup", "inf", "max", "min",
        "det", "ker", "im", "tr", "rank", "def", "dim", "sgn",
        "sign", "grad", "div", "curl", "mod", "gcd", "lcm",
        "arg", "Re", "Im", "deg", "hom", "coker", "coim",
        "Pr", "mathbb", "mathbf", "mathrm", "mathcal", "text"
    ]

    /// Characters that are valid INSIDE a math expression (besides letters/digits).
    nonisolated static let mathPunctChars: Set<Character> = Set("^_{}()[]+-=<>/!|,.'*~;:")

    /// Shared KaTeX macro aliases used by the app renderers.
    ///
    /// Keep this list conservative:
    /// - allow additive shorthand aliases that preserve meaning
    /// - avoid remapping built-in commands to different glyphs
    /// - avoid overriding standard relations such as `\neq`
    nonisolated static let katexExtraMacros: [String: String] = [
        "\\thinspace": "\\,",
        "\\negthinspace": "\\!",
        "\\medspace": "\\:",
        "\\thickspace": "\\;",
        "\\R": "\\mathbb{R}",
        "\\N": "\\mathbb{N}",
        "\\Z": "\\mathbb{Z}",
        "\\Q": "\\mathbb{Q}",
        "\\C": "\\mathbb{C}",
        "\\eps": "\\epsilon"
    ]

    nonisolated static var katexExtraMacrosJSObjectLiteral: String {
        katexExtraMacros
            .sorted { $0.key < $1.key }
            .map { key, value in
            let escapedKey = key
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let escapedValue = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "            \"\(escapedKey)\": \"\(escapedValue)\""
        }
            .joined(separator: ",\n")
    }

    /// HTML tags for loading bundled KaTeX assets with font URLs rewritten to
    /// absolute bundle locations.
    nonisolated static func katexLocalHTMLTags() -> String? {
        guard
            let jsURL = Bundle.main.url(forResource: "katex.min", withExtension: "js"),
            let cssURL = Bundle.main.url(forResource: "katex.min", withExtension: "css"),
            let autoRenderURL = Bundle.main.url(forResource: "auto-render.min", withExtension: "js"),
            let rawCSS = try? String(contentsOf: cssURL),
            let embeddedCSS = rewrittenKatexCSS(rawCSS)
            else {
            return nil
        }

        let safeCSS = embeddedCSS.replacingOccurrences(of: "</style", with: "<\\/style")
        return """
        <style>
        \(safeCSS)
        </style>
        <script src="\(jsURL.absoluteString)"></script>
        <script src="\(autoRenderURL.absoluteString)"></script>
        """
    }

    // -------------------------------------------------------------------------
    // MARK: - Public API
    // -------------------------------------------------------------------------

    /// Main entry point. Call this on every string before rendering rich content.
    nonisolated static func heal(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        text = normalizeJSONEscapedLatexCommands(text)
        text = normalizeDetachedPunctuation(text)
        text = applyWidowControl(text)
        text = repairBareLatexDelimiters(text)
        text = fixOrphanDollar(text)
        text = stripInvalidMathTokens(text)
        return text
    }

    /// Returns a cheap fallback suitable for the deck grid.
    ///
    /// Preserves lightweight markdown markers (`**bold**`, `` `code` ``) so the
    /// SwiftUI fallback renderer can still style them locally, while flattening
    /// common LaTeX wrappers into human-readable preview text.
    nonisolated static func normalizedPreview(_ input: String) -> String {
        let source = input.replacingOccurrences(of: "\r\n", with: "\n")
        var result = ""
        var cursor = source.startIndex

        while cursor < source.endIndex {
            if source[cursor] == "`",
                let closing = source[source.index(after: cursor)...].firstIndex(of: "`") {
                let innerRange = source.index(after: cursor)..<closing
                let inner = String(source[innerRange])
                result += "`\(normalizedCodeLiteral(inner))`"
                cursor = source.index(after: closing)
                continue
            }

            let nextCode = source[cursor...].firstIndex(of: "`") ?? source.endIndex
            let segment = String(source[cursor..<nextCode])
            result += normalizedPlainPreviewSegment(segment)
            cursor = nextCode
        }

        let collapsedLines = result
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
            line.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
            .joined(separator: "\n")

        return collapsedLines.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Normalizes inline-code payloads into readable plain text while preserving
    /// their semantic code wrapper for the preview renderer.
    nonisolated static func normalizedCodeLiteral(_ input: String) -> String {
        flattenPreviewLatex(in: input)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes a single terminal period from a rendered zone without mutating
    /// any stored content. This is intentionally conservative:
    /// - removes only one final `.`
    /// - preserves ellipses and all other punctuation
    nonisolated static func stripTerminalZonePeriod(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let regex = try? NSRegularExpression(pattern: #"(?<!\.)\.(?=\s*$)"#)
            else {
            return trimmed
        }

        return regex.stringByReplacingMatches(
            in: trimmed,
            range: NSRange(trimmed.startIndex..., in: trimmed),
            withTemplate: ""
        )
    }

    /// Removes a single terminal period without changing author-entered spacing.
    nonisolated static func stripTerminalZonePeriodPreservingWhitespace(_ input: String) -> String {
        guard
            let regex = try? NSRegularExpression(pattern: #"(?<!\.)\.(?=\s*$)"#)
            else {
            return input
        }

        return regex.stringByReplacingMatches(
            in: input,
            range: NSRange(input.startIndex..., in: input),
            withTemplate: ""
        )
    }

    /// Returns true if rich rendering would materially improve this string.
    nonisolated static func needsRichPreview(_ input: String) -> Bool {
        let healed = heal(input)
        return containsMath(healed) || containsInlineCode(healed)
    }

    /// Returns true if text contains math that needs WebView rendering.
    nonisolated static func containsMath(_ text: String) -> Bool {
        if text.contains("$") || text.contains("\\[") ||
            text.contains("\\(") || text.contains("\\begin") {
            return true
        }
        return hasBareLatexCommand(text)
    }

    nonisolated static func containsInlineCode(_ text: String) -> Bool {
        let pattern = "`[^`]+`"
        return (try? NSRegularExpression(pattern: pattern))
            .map { $0.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
            ?? false
    }

    /// Returns true when the text contains display math that may overflow the
    /// available width and should opt into local horizontal scrolling.
    nonisolated static func containsDisplayMath(_ text: String) -> Bool {
        text.contains("$$") || text.contains("\\[") || text.contains("\\begin{")
    }

    // -------------------------------------------------------------------------
    // MARK: - Preview Flattening
    // -------------------------------------------------------------------------

    nonisolated static func normalizedPlainPreviewSegment(_ input: String) -> String {
        flattenPreviewLatex(in: heal(input))
    }

    nonisolated static func flattenPreviewLatex(in input: String) -> String {
        var result = input

        let wrapperCommands = [
            "text", "mathrm", "mathbf", "mathit", "mathsf", "mathtt",
            "operatorname", "mathcal", "mathbb"
        ]

        for command in wrapperCommands {
            let pattern = "\\\\\(command)\\{([^{}]*)\\}"
            while let regex = try? NSRegularExpression(pattern: pattern) {
                let next = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: "$1"
                )
                if next == result { break }
                result = next
            }
        }

        let replacements: [(pattern: String, replacement: String)] = [
            ("\\\\rightarrow", "→"),
            ("\\\\Rightarrow", "⇒"),
            ("\\\\leftrightarrow", "↔"),
            ("\\\\Leftrightarrow", "⇔"),
            ("\\\\mapsto", "↦"),
            ("\\\\to", "→"),
            ("\\\\implies", "⇒"),
            ("\\\\iff", "⇔"),
            ("\\\\land", "∧"),
            ("\\\\lor", "∨"),
            ("\\\\neg", "¬"),
            ("\\\\lnot", "¬"),
            ("\\\\in", "∈"),
            ("\\\\notin", "∉"),
            ("\\\\subseteq", "⊆"),
            ("\\\\subset", "⊂"),
            ("\\\\cup", "∪"),
            ("\\\\cap", "∩"),
            ("\\\\forall", "∀"),
            ("\\\\exists", "∃"),
            ("\\\\cdot", "·"),
            ("\\\\times", "×"),
            ("\\\\geq", "≥"),
            ("\\\\leq", "≤"),
            ("\\\\neq", "≠"),
            ("\\\\,", " "),
            ("\\\\;", " "),
            ("\\\\:", " "),
            ("\\\\!", "")
        ]

        for replacement in replacements {
            result = result.replacingOccurrences(
                of: replacement.pattern,
                with: replacement.replacement,
                options: .regularExpression
            )
        }

        result = result.replacingOccurrences(
            of: #"\\([{}])"#,
            with: "$1",
            options: .regularExpression
        )

        return result
    }

    // -------------------------------------------------------------------------
    // MARK: - KaTeX Asset Rewriting
    // -------------------------------------------------------------------------

    private nonisolated static func rewrittenKatexCSS(_ css: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"url\((['"]?)fonts/([^)'"]+)\1\)"#) else {
            return css
        }

        let matches = regex.matches(in: css, range: NSRange(css.startIndex..., in: css))
        guard !matches.isEmpty else { return css }

        var rewritten = css
        for match in matches.reversed() {
            guard
                let fullRange = Range(match.range, in: rewritten),
                let fileNameRange = Range(match.range(at: 2), in: rewritten)
                else { continue }

            let fileName = String(rewritten[fileNameRange])
            let nsFileName = fileName as NSString
            let resourceName = nsFileName.deletingPathExtension
            let fileExtension = nsFileName.pathExtension

            guard
            !resourceName.isEmpty,
                !fileExtension.isEmpty,
                let resolvedURL = Bundle.main.url(forResource: resourceName, withExtension: fileExtension)
                else {
                continue
            }

            rewritten.replaceSubrange(fullRange, with: "url('\(resolvedURL.absoluteString)')")
        }

        return rewritten
    }

    // =========================================================================
    // MARK: - Core: Bare LaTeX Repair
    // =========================================================================

    /// Reattaches punctuation that ended up separated from the preceding token
    /// by spaces or newlines, e.g. `B' \n .` -> `B'.`
    nonisolated static func normalizeDetachedPunctuation(_ input: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\s+([.,;:!?])"#) else {
            return input
        }

        return regex.stringByReplacingMatches(
            in: input,
            range: NSRange(input.startIndex..., in: input),
            withTemplate: "$1"
        )
    }

    /// Reduces typographic widows/orphans on narrow screens by making the final
    /// break in each paragraph non-breaking. This is especially useful when a
    /// zone ends in inline math like `$B'$.`, where the browser may otherwise
    /// leave the punctuation or the final short fragment alone on the last line.
    nonisolated static func applyWidowControl(_ input: String) -> String {
        input
            .components(separatedBy: "\n")
            .map(makeFinalBreakNonBreaking)
            .joined(separator: "\n")
    }

    private nonisolated static func makeFinalBreakNonBreaking(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return line }

        // Replace the last regular whitespace run with a non-breaking space.
        // This keeps the last fragment attached to what precedes it, but does
        // not disturb earlier wrapping decisions.
        guard let regex = try? NSRegularExpression(pattern: #"\s+(?=\S+\s*$)"#) else {
            return line
        }

        let range = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, range: range)
        guard let last = matches.last, let lastRange = Range(last.range, in: line) else {
            return line
        }

        let trailingFragment = String(line[lastRange.upperBound...])
        guard shouldKeepFinalFragmentTogether(trailingFragment) else {
            return line
        }

        var result = line
        result.replaceSubrange(lastRange, with: "\u{00A0}")
        return result
    }

    private nonisolated static func shouldKeepFinalFragmentTogether(_ fragment: String) -> Bool {
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Keep final math/code fragments attached, but let normal language
        // reflow naturally in the actual play container.
        if trimmed.contains("$") || trimmed.contains("\\") || trimmed.contains("`") {
            return true
        }

        return trimmed.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2200...0x22FF, // mathematical operators
             0x2100...0x214F, // letterlike symbols
             0x2190...0x21FF: // arrows
                return true
            default:
                return false
            }
        }
    }

    /// Collapses JSON-escaped LaTeX commands such as `\\neq` into `\neq`.
    ///
    /// This keeps normal TeX line breaks intact because those use `\\`
    /// followed by whitespace or structure, not by command letters.
    nonisolated static func normalizeJSONEscapedLatexCommands(_ input: String) -> String {
        guard input.contains("\\\\") else { return input }
        guard let regex = try? NSRegularExpression(pattern: #"\\\\([A-Za-z]+)"#) else {
            return input
        }

        return regex.stringByReplacingMatches(
            in: input,
            range: NSRange(input.startIndex..., in: input),
            withTemplate: #"\\$1"#
        )
    }

    /// Wraps LaTeX commands that appear outside $…$ in proper delimiters.
    nonisolated static func repairBareLatexDelimiters(_ text: String) -> String {
        guard hasBareLatexCommand(text) else { return text }

        let lines = text.components(separatedBy: "\n")
        return lines.map { repairLine($0) }.joined(separator: "\n")
    }

    // -------------------------------------------------------------------------
    // MARK: - Line-level Repair
    // -------------------------------------------------------------------------

    nonisolated static func repairLine(_ line: String) -> String {
        guard hasBareLatexCommand(line) else { return line }

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let (listPrefix, content) = extractListPrefix(trimmed)

        if looksLikePureMathExpression(content) {
            let useBlock = content.contains("\\begin{")
                || content.contains("\\frac{")
                || content.contains("\\int")
                || content.contains("\\sum")
                || content.contains("\\prod")
                || content.count > 80
            let delimiter = useBlock ? "$$" : "$"
            let wrapped = "\(delimiter)\(content)\(delimiter)"
            let indent = String(line.prefix(line.count - line.drop(while: { $0 == " " || $0 == "\t" }).count))
            return "\(indent)\(listPrefix)\(wrapped)"
        }

        return wrapBareSegmentsInLine(line)
    }

    // -------------------------------------------------------------------------
    // MARK: - Segment Scanner (character-level)
    // -------------------------------------------------------------------------

    nonisolated static func wrapBareSegmentsInLine(_ line: String) -> String {
        var result = ""
        var index = line.startIndex
        var inSingleDollar = false
        var inDoubleDollar = false

        while index < line.endIndex {
            let character = line[index]

            if character == "$" {
                let next = line.index(after: index)
                if next < line.endIndex && line[next] == "$" {
                    inDoubleDollar.toggle()
                    result += "$$"
                    index = line.index(after: next)
                    continue
                }

                inSingleDollar.toggle()
                result.append(character)
                index = line.index(after: index)
                continue
            }

            if character == "\\" && !inSingleDollar && !inDoubleDollar {
                let next = line.index(after: index)
                if next < line.endIndex {
                    let nextCharacter = line[next]
                    if nextCharacter.isLetter || nextCharacter == "{" || nextCharacter == "}" || nextCharacter == "|" || nextCharacter == "," {
                        let (prefix, trimmedResult) = absorbPrecedingMathChars(from: result)
                        result = trimmedResult

                        let (mathSegment, endIndex) = collectMathSegment(in: line, from: index)

                        if mathSegment.isEmpty {
                            result = trimmedResult + prefix
                            result.append(character)
                            index = line.index(after: index)
                        } else {
                            result += "$\(prefix)\(mathSegment)$"
                            index = endIndex
                        }
                        continue
                    }
                }
            }

            result.append(character)
            index = line.index(after: index)
        }

        return result
    }

    nonisolated static func absorbPrecedingMathChars(from result: String) -> (prefix: String, trimmed: String) {
        var prefix = ""
        var trimmed = result

        while let last = trimmed.last {
            if (last.isLetter && prefix.isEmpty) || (last.isNumber && prefix.isEmpty) {
                prefix = String(last) + prefix
                trimmed.removeLast()
            } else {
                break
            }
        }

        return (prefix, trimmed)
    }

    // -------------------------------------------------------------------------
    // MARK: - Math Segment Collector
    // -------------------------------------------------------------------------

    nonisolated static func collectMathSegment(in text: String, from start: String.Index) -> (String, String.Index) {
        var segment = ""
        var index = start
        var braceDepth = 0

        while index < text.endIndex {
            let character = text[index]

            if character == "\n" || character == "$" { break }

            if character == "\\" {
                let nextIndex = text.index(after: index)
                guard nextIndex < text.endIndex else { break }
                let nextCharacter = text[nextIndex]

                if nextCharacter.isLetter {
                    segment.append(character)
                    var commandIndex = nextIndex
                    while commandIndex < text.endIndex && text[commandIndex].isLetter {
                        segment.append(text[commandIndex])
                        commandIndex = text.index(after: commandIndex)
                    }
                    index = commandIndex
                    continue
                }

                let escapable: Set<Character> = ["{", "}", "|", ",", ";", ":", ".", "!", "\\", " ", "(", ")", "[", "]"]
                if escapable.contains(nextCharacter) {
                    segment.append(character)
                    segment.append(nextCharacter)
                    index = text.index(after: nextIndex)
                    continue
                }

                break
            }

            if character == "{" {
                braceDepth += 1
                segment.append(character)
                index = text.index(after: index)
                continue
            }

            if character == "}" {
                if braceDepth <= 0 { break }
                braceDepth -= 1
                segment.append(character)
                index = text.index(after: index)
                continue
            }

            if character == " " || character == "\t" {
                let nextWord = peekNextWord(in: text, from: text.index(after: index))
                if mathContinues(after: nextWord, braceDepth: braceDepth) {
                    segment.append(" ")
                    index = text.index(after: index)
                } else {
                    break
                }
                continue
            }

            if isMathCompatibleChar(character) {
                segment.append(character)
                index = text.index(after: index)
            } else {
                break
            }
        }

        let trimmed = segment.trimmingCharacters(in: CharacterSet(charactersIn: ",; \t"))
        return (trimmed, index)
    }

    // -------------------------------------------------------------------------
    // MARK: - Decision Helpers
    // -------------------------------------------------------------------------

    nonisolated static func peekNextWord(in text: String, from start: String.Index) -> String {
        var index = start
        while index < text.endIndex && text[index] == " " {
            index = text.index(after: index)
        }

        var word = ""
        while index < text.endIndex {
            let character = text[index]
            if character.isWhitespace || character == "\n" || character == "$" { break }
            word.append(character)
            index = text.index(after: index)
        }
        return word
    }

    nonisolated static func mathContinues(after nextWord: String, braceDepth: Int) -> Bool {
        if nextWord.isEmpty { return false }
        if braceDepth > 0 { return true }
        if nextWord.hasPrefix("\\") { return true }
        if nextWord.hasPrefix("^") || nextWord.hasPrefix("_") { return true }
        if nextWord.hasPrefix("{") || nextWord.hasPrefix("(") || nextWord.hasPrefix("[") { return true }

        let stripped = nextWord.trimmingCharacters(in: CharacterSet(charactersIn: "{}()[]^_.,;:!"))
        if stripped.count == 1 && stripped.first?.isASCIILetter == true { return true }
        if mathFunctionNames.contains(stripped.lowercased()) { return true }
        if nextWord.contains("=") || nextWord.contains("^") || nextWord.contains("_") { return true }
        if stripped.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" || $0 == "," }) { return true }

        return false
    }

    nonisolated static func isMathCompatibleChar(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || mathPunctChars.contains(character)
    }

    // -------------------------------------------------------------------------
    // MARK: - Pure-Math Expression Detection
    // -------------------------------------------------------------------------

    nonisolated static func looksLikePureMathExpression(_ text: String) -> Bool {
        guard hasBareLatexCommand(text) else { return false }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        let words = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var naturalWordCount = 0

        for word in words {
            let clean = word.trimmingCharacters(in: CharacterSet(charactersIn: "{}()[]^_+-=<>/!|,;.:$\\"))
            if clean.isEmpty { continue }
            if word.hasPrefix("\\") { continue }
            if clean.count <= 2 { continue }
            if mathFunctionNames.contains(clean.lowercased()) { continue }

            let hasMathCharacter = clean.contains(where: { "^_{}()\\/=<>!|".contains($0) || $0.isNumber })
            if hasMathCharacter { continue }

            if clean.allSatisfy({ $0.isLetter }) && clean.count >= 3 {
                naturalWordCount += 1
            }
        }

        return naturalWordCount == 0
    }

    // -------------------------------------------------------------------------
    // MARK: - Bare Command Detection
    // -------------------------------------------------------------------------

    nonisolated static func hasBareLatexCommand(_ text: String) -> Bool {
        guard text.contains("\\") else { return false }

        var inDollar = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            let nextIndex = text.index(after: index)

            if character == "$" {
                if nextIndex < text.endIndex && text[nextIndex] == "$" {
                    inDollar.toggle()
                    index = text.index(after: nextIndex)
                    continue
                }

                inDollar.toggle()
                index = nextIndex
                continue
            }

            if character == "\\" && !inDollar && nextIndex < text.endIndex {
                let nextCharacter = text[nextIndex]
                if nextCharacter.isLetter || nextCharacter == "{" || nextCharacter == "}" || nextCharacter == "|" {
                    return true
                }
            }

            index = nextIndex
        }

        return false
    }

    // -------------------------------------------------------------------------
    // MARK: - List Prefix Extraction
    // -------------------------------------------------------------------------

    nonisolated static func extractListPrefix(_ line: String) -> (prefix: String, content: String) {
        let patterns = [
            #"^(\s*(?:-|\*|•)\s+)"#,
            #"^(\s*\d+[.)]\s+)"#,
            #"^(\s*[a-zA-Z][.)]\s+)"#,
            #"^(\s*\([a-zA-Z0-9]+\)\s+)"#
        ]
        for pattern in patterns {
            if let range = line.range(of: pattern, options: .regularExpression) {
                return (String(line[range]), String(line[range.upperBound...]))
            }
        }
        return ("", line)
    }

    // -------------------------------------------------------------------------
    // MARK: - Legacy Sanitizers
    // -------------------------------------------------------------------------

    nonisolated static func fixOrphanDollar(_ input: String) -> String {
        var text = input
        var singles = 0
        var index = text.startIndex

        while index < text.endIndex {
            if text[index] == "$" {
                let next = text.index(after: index)
                if next < text.endIndex && text[next] == "$" {
                    index = text.index(after: next)
                } else {
                    singles += 1
                    index = next
                }
            } else {
                index = text.index(after: index)
            }
        }

        guard singles % 2 != 0 else { return text }
        if let last = text.lastIndex(of: "$") {
            let previous = last > text.startIndex ? text.index(before: last) : nil
            if previous == nil || text[previous!] != "$" {
                text.remove(at: last)
            }
        }
        return text
    }

    nonisolated static func stripInvalidMathTokens(_ input: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "€£¥₹₩₿¢฿₪₨₦")
        guard let regex = try? NSRegularExpression(
            pattern: "(?<!\\$)\\$(?!\\$)(.+?)(?<!\\$)\\$(?!\\$)"
        ) else { return input }

        var result = input
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                let innerRange = Range(match.range(at: 1), in: result) else { continue }
            let inner = String(result[innerRange])
            if inner.unicodeScalars.contains(where: { invalidChars.contains($0) }) {
                result.replaceSubrange(fullRange, with: inner)
            }
        }
        return result
    }
}

private extension Character {
    nonisolated var isASCIILetter: Bool { isASCII && isLetter }
}
