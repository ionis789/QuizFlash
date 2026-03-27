import Foundation
import UIKit
import SwiftData

extension AIFlashcardService {
    func parseResponseContent(from data: Data) throws -> String {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any]
        else {
            throw AIServiceError.parsingFailed
        }

        if let content = message["content"] as? String {
            return content
        }

        if let contentParts = message["content"] as? [[String: Any]] {
            let text = contentParts.compactMap { part -> String? in
                if let text = part["text"] as? String { return text }
                return nil
            }
            .joined(separator: "\n")

            if !text.isEmpty {
                return text
            }
        }

        throw AIServiceError.parsingFailed
    }

    func supportsTemperatureParameter(for model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !normalized.hasPrefix("gpt-5")
    }

    func apiErrorMessage(from data: Data, statusCode: Int) -> String {
        if
            let decoded = try? JSONDecoder().decode(AIProviderErrorEnvelope.self, from: data),
            let message = decoded.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines),
            !message.isEmpty
        {
            return "\(provider.trimmedName) HTTP \(statusCode): \(message)"
        }

        if
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? [String: Any],
            let message = error["message"] as? String,
            !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return "\(provider.trimmedName) HTTP \(statusCode): \(message)"
        }

        if
            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        {
            return "\(provider.trimmedName) HTTP \(statusCode): \(raw)"
        }

        return "\(provider.trimmedName) HTTP \(statusCode)"
    }

    func decodeGeneratedCards(
        from jsonString: String,
        contract: AIGeneratedCardContract
    ) throws -> [AIFlashcard] {
        // Strip markdown code fences if present (shouldn't happen with json_object mode, but defensive)
        var clean = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        if clean.hasPrefix("```json") {
            clean = String(clean.dropFirst(7))
        } else if clean.hasPrefix("```") {
            clean = String(clean.dropFirst(3))
        }
        if clean.hasSuffix("```") {
            clean = String(clean.dropLast(3))
        }

        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)

        clean = fixLatexEscaping(in: clean)
        guard let data = clean.data(using: .utf8) else {
            throw AIServiceError.parsingFailed
        }

        do {
            switch contract {
            case .flashcard:
                let dto = try JSONDecoder().decode(FlashcardResponseDTO.self, from: data)
                let cards = dto.resolvedCards
                guard !cards.isEmpty else { throw AIServiceError.parsingFailed }

                return cards.map { card in
                    let questionZones = sanitizedZoneStrings(card.resolvedQuestionZones)
                    let answerZones = sanitizedZoneStrings(card.answer_zones)

                    return AIFlashcard(
                        id: UUID(),
                        content: .flashcard(
                            AIFlashcardContent(
                                questionZones: questionZones.isEmpty ? card.resolvedQuestionZones : questionZones,
                                answerZones: answerZones.isEmpty ? card.answer_zones : answerZones
                            )
                        )
                    )
                }
            case .match:
                let dto = try JSONDecoder().decode(MatchResponseDTO.self, from: data)
                guard !dto.cards.isEmpty else { throw AIServiceError.parsingFailed }

                return try dto.cards.map { card in
                    let prompt = normalizedMatchText(card.prompt)
                    let answer = normalizedMatchText(card.answer)

                    guard !prompt.isEmpty, !answer.isEmpty else {
                        throw AIServiceError.parsingFailed
                    }

                    return AIFlashcard(
                        id: UUID(),
                        content: .match(
                            AIMatchCardContent(
                                prompt: prompt,
                                answer: answer
                            )
                        )
                    )
                }
            case .quiz:
                let dto = try JSONDecoder().decode(QuizResponseDTO.self, from: data)
                guard !dto.cards.isEmpty else { throw AIServiceError.parsingFailed }

                return try dto.cards.map { card in
                    let questionZones = sanitizedZoneStrings(card.question_zones)
                    let choices = card.choices
                        .map { AIZoneParser.sanitizeLatex($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    let correctIndexes = normalizedCorrectIndexes(card.correct_indexes, choiceCount: choices.count)
                    let explanationZones = sanitizedZoneStrings(card.explanation_zones ?? [])

                    guard !questionZones.isEmpty, choices.count >= 2, !correctIndexes.isEmpty else {
                        throw AIServiceError.parsingFailed
                    }

                    return AIFlashcard(
                        id: UUID(),
                        content: .quiz(
                            AIQuizCardContent(
                                questionZones: questionZones,
                                choices: choices,
                                correctIndexes: correctIndexes,
                                explanationZones: explanationZones.isEmpty ? nil : explanationZones
                            )
                        )
                    )
                }
            case .write:
                let dto = try JSONDecoder().decode(WriteResponseDTO.self, from: data)
                guard !dto.cards.isEmpty else { throw AIServiceError.parsingFailed }

                return try dto.cards.map { card in
                    let sourceText = AIZoneParser.sanitizeLatex(card.source_text)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let omittedText = AIZoneParser.sanitizeLatex(card.omitted_text)
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    guard !sourceText.isEmpty, !omittedText.isEmpty else {
                        throw AIServiceError.parsingFailed
                    }

                    return AIFlashcard(
                        id: UUID(),
                        content: .write(
                            AIWriteCardContent(
                                sourceText: sourceText,
                                omittedText: omittedText
                            )
                        )
                    )
                }
            }
        } catch {
            throw AIServiceError.parsingFailed
        }
    }

    func decodeConvertedCards(
        from jsonString: String,
        sourceCards: [AICardConversionSource],
        contract: AIGeneratedCardContract
    ) throws -> [AICardConversionOutput] {
        var clean = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        if clean.hasPrefix("```json") {
            clean = String(clean.dropFirst(7))
        } else if clean.hasPrefix("```") {
            clean = String(clean.dropFirst(3))
        }
        if clean.hasSuffix("```") {
            clean = String(clean.dropLast(3))
        }

        clean = fixLatexEscaping(in: clean.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let data = clean.data(using: .utf8) else {
            throw AIServiceError.parsingFailed
        }

        func mappedOutputs<T>(
            _ results: [T],
            sourceIndex: (T) -> Int,
            makeCard: (T) throws -> AIFlashcard
        ) throws -> [AICardConversionOutput] {
            guard results.count == sourceCards.count else {
                throw AIServiceError.parsingFailed
            }

            let outputs = try results.map { result -> AICardConversionOutput in
                let index = sourceIndex(result)
                guard sourceCards.indices.contains(index) else {
                    throw AIServiceError.parsingFailed
                }
                return AICardConversionOutput(
                    sourceCardID: sourceCards[index].id,
                    generatedCard: try makeCard(result)
                )
            }

            let uniqueSourceIDs = Set(outputs.map(\.sourceCardID))
            guard uniqueSourceIDs.count == sourceCards.count else {
                throw AIServiceError.parsingFailed
            }

            return outputs
        }

        switch contract {
        case .flashcard:
            let dto = try JSONDecoder().decode(FlashcardConversionResponseDTO.self, from: data)
            return try mappedOutputs(dto.results, sourceIndex: \.source_index) { result in
                AIFlashcard(
                    content: .flashcard(
                        AIFlashcardContent(
                            questionZones: sanitizedZoneStrings(result.question_zones),
                            answerZones: sanitizedZoneStrings(result.answer_zones)
                        )
                    )
                )
            }
        case .match:
            let dto = try JSONDecoder().decode(MatchConversionResponseDTO.self, from: data)
            return try mappedOutputs(dto.results, sourceIndex: \.source_index) { result in
                AIFlashcard(
                    content: .match(
                        AIMatchCardContent(
                            prompt: normalizedMatchText(result.prompt),
                            answer: normalizedMatchText(result.answer)
                        )
                    )
                )
            }
        case .quiz:
            let dto = try JSONDecoder().decode(QuizConversionResponseDTO.self, from: data)
            return try mappedOutputs(dto.results, sourceIndex: \.source_index) { result in
                let questionZones = sanitizedZoneStrings(result.question_zones)
                let choices = result.choices
                    .map { AIZoneParser.sanitizeLatex($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let correctIndexes = normalizedCorrectIndexes(result.correct_indexes, choiceCount: choices.count)
                let explanationZones = sanitizedZoneStrings(result.explanation_zones ?? [])

                guard !questionZones.isEmpty, choices.count >= 2, !correctIndexes.isEmpty else {
                    throw AIServiceError.parsingFailed
                }

                return AIFlashcard(
                    content: .quiz(
                        AIQuizCardContent(
                            questionZones: questionZones,
                            choices: choices,
                            correctIndexes: correctIndexes,
                            explanationZones: explanationZones.isEmpty ? nil : explanationZones
                        )
                    )
                )
            }
        case .write:
            let dto = try JSONDecoder().decode(WriteConversionResponseDTO.self, from: data)
            return try mappedOutputs(dto.results, sourceIndex: \.source_index) { result in
                let sourceText = AIZoneParser.sanitizeLatex(result.source_text)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let omittedText = AIZoneParser.sanitizeLatex(result.omitted_text)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !sourceText.isEmpty, !omittedText.isEmpty else {
                    throw AIServiceError.parsingFailed
                }

                return AIFlashcard(
                    content: .write(
                        AIWriteCardContent(
                            sourceText: sourceText,
                            omittedText: omittedText
                        )
                    )
                )
            }
        }
    }

    nonisolated func conversionSourceBody(for content: DraftCardContent) -> String {
        switch content {
        case .flashcard(let content):
            return """
            FRONT:
            \(sanitizedConversionBlock(content.frontZone.previewText(maxLength: 1_200)))

            BACK:
            \(sanitizedConversionBlock(content.backZone.previewText(maxLength: 1_200)))
            """
        case .match(let content):
            return """
            PROMPT:
            \(sanitizedConversionLine(content.prompt))

            ANSWER:
            \(sanitizedConversionLine(content.answer))
            """
        case .quiz(let content):
            let choices = content.choices.enumerated().map { index, choice in
                let prefix = choice.isCorrect ? "[correct]" : "[option]"
                return "\(index). \(prefix) \(sanitizedConversionLine(choice.contentZone.previewText(maxLength: 240)))"
            }
            .joined(separator: "\n")

            let explanation = content.explanationZone?.previewText(maxLength: 800) ?? ""
            let explanationSection = explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "EXPLANATION:\nNone"
                : "EXPLANATION:\n\(sanitizedConversionBlock(explanation))"

            return """
            QUESTION:
            \(sanitizedConversionBlock(content.questionZone.previewText(maxLength: 1_000)))

            CHOICES:
            \(choices)

            \(explanationSection)
            """
        case .write(let content):
            return """
            SOURCE_TEXT:
            \(sanitizedConversionBlock(content.sourceZone.previewText(maxLength: 1_200)))

            OMITTED_TEXT:
            \(sanitizedConversionLine(content.blankSelection.omittedText))
            """
        }
    }

    func sanitizedZoneStrings(_ values: [String]) -> [String] {
        values
            .map { AIZoneParser.sanitizeLatex($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    nonisolated func sanitizedConversionBlock(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Empty" }
        return trimmed
    }

    nonisolated func sanitizedConversionLine(_ value: String) -> String {
        let trimmed = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Empty" }
        return trimmed
    }

    func normalizedMatchText(_ value: String) -> String {
        AIZoneParser.sanitizeLatex(value)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func normalizedCorrectIndexes(_ indexes: [Int], choiceCount: Int) -> [Int] {
        let validIndexes = indexes.filter { $0 >= 0 && $0 < choiceCount }
        return Array(Set(validIndexes)).sorted()
    }
    // -------------------------------------------------------------------------
    // MARK: - LaTeX JSON Escape Fixer  (runs on RAW JSON string, before JSONDecoder)
    // -------------------------------------------------------------------------

    /// GPT sometimes writes LaTeX commands with a SINGLE backslash inside JSON
    /// (e.g. `\lambda`), which is an invalid JSON escape sequence.  JSONDecoder
    /// would either throw or silently drop the backslash, producing `lambda`.
    ///
    /// This function runs on the raw JSON TEXT (before decoding) and ensures
    /// every LaTeX command has exactly two backslashes (\\command), so that
    /// after JSONDecoder the Swift String contains the correct single \command.
    ///
    /// Strategy:
    ///   • Regex: find a single backslash (not preceded by another backslash)
    ///     followed by a known LaTeX command name.
    ///   • Replace with \\command.
    ///
    /// Over-escaping (\\\\command → \\command) is handled POST-decode in
    /// AIZoneParser.fixOverescapedLatex(), which is simpler and safer there.
    func fixLatexEscaping(in jsonString: String) -> String {
        // Comprehensive list — all common LaTeX math commands.
        // Grouped for readability; order does not matter for the regex.
        let commands = [
            // Greek lowercase
            "alpha", "beta", "gamma", "delta", "epsilon", "varepsilon",
            "zeta", "eta", "theta", "vartheta", "iota", "kappa", "lambda",
            "mu", "nu", "xi", "pi", "varpi", "rho", "varrho", "sigma",
            "varsigma", "tau", "upsilon", "phi", "varphi", "chi", "psi", "omega",
            // Greek uppercase
            "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi", "Sigma",
            "Upsilon", "Phi", "Psi", "Omega",
            // Arrows
            "to", "rightarrow", "Rightarrow", "leftarrow", "Leftarrow",
            "leftrightarrow", "Leftrightarrow", "mapsto", "hookrightarrow",
            "nrightarrow", "nRightarrow", "uparrow", "downarrow",
            "nearrow", "searrow", "swarrow", "nwarrow",
            // Set / logic
            "in", "notin", "ni", "subset", "subseteq", "supset", "supseteq",
            "cup", "cap", "bigcup", "bigcap", "setminus", "emptyset",
            "forall", "exists", "nexists", "neg", "lnot", "wedge", "vee",
            "land", "lor", "Rightarrow", "Leftrightarrow", "equiv",
            // Relations / comparison
            "leq", "geq", "neq", "approx", "sim", "simeq", "cong",
            "ll", "gg", "prec", "succ", "perp", "parallel", "mid", "nmid",
            // Operators
            "cdot", "times", "div", "oplus", "otimes", "circ", "bullet",
            "pm", "mp", "star", "ast", "dagger", "ddagger",
            // Big operators
            "sum", "prod", "coprod", "int", "oint", "iint", "iiint",
            "bigoplus", "bigotimes", "bigsqcup", "biguplus", "bigvee", "bigwedge",
            // Fractions / roots
            "frac", "dfrac", "tfrac", "cfrac", "sqrt", "over",
            // Delimiters
            "left", "right", "langle", "rangle", "lfloor", "rfloor",
            "lceil", "rceil", "lbrace", "rbrace", "vert", "Vert",
            // Dots
            "ldots", "cdots", "vdots", "ddots", "dots",
            // Functions (math mode)
            "sin", "cos", "tan", "cot", "sec", "csc",
            "arcsin", "arccos", "arctan",
            "sinh", "cosh", "tanh",
            "log", "ln", "exp", "lim", "limsup", "liminf",
            "sup", "inf", "max", "min", "gcd", "lcm", "det",
            "ker", "dim", "deg", "hom", "arg", "Pr", "mod",
            // Accents / decorators
            "hat", "bar", "tilde", "vec", "dot", "ddot", "widetilde",
            "widehat", "overline", "underline", "overbrace", "underbrace",
            "overset", "underset",
            // Environments / structure
            "begin", "end", "text", "mathrm", "mathbf", "mathbb", "mathcal",
            "mathit", "mathsf", "mathtt", "boldsymbol", "operatorname",
            "textbf", "textit", "texttt",
            // Spacing
            "quad", "qquad",
            // Misc math
            "infty", "partial", "nabla", "triangle", "angle", "measuredangle",
            "prime", "backslash", "textbackslash",
            "not", "iff", "implies", "therefore", "because",
            "rank", "span", "trace", "tr", "sgn", "sign",
            "colon", "coloneq", "eqcolon",
            "flat", "natural", "sharp",
            "Re", "Im", "top", "bot", "ell",
            // Matrix environments
            "pmatrix", "bmatrix", "vmatrix", "Vmatrix", "matrix",
            "cases", "aligned", "align", "gather", "equation",
            "array", "substack",
            // Display layout
            "displaystyle", "textstyle", "scriptstyle", "scriptscriptstyle",
            "limits", "nolimits",
            "label", "tag", "nonumber",
        ].joined(separator: "|")

        // Match a SINGLE backslash (not preceded by another backslash)
        // followed immediately by one of the command names, at a word boundary.
        let pattern = #"(?<!\\)\\(?!\\)(\#(commands))\b"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return jsonString
        }

        let range = NSRange(jsonString.startIndex..., in: jsonString)
        // Replace \command → \\command (valid JSON escape)
        return regex.stringByReplacingMatches(
            in: jsonString,
            options: [],
            range: range,
            withTemplate: #"\\\\$1"#
        )
    }
}
