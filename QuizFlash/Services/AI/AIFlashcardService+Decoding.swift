import Foundation

extension AIFlashcardService {
    func parseResponseContent(from data: Data) async throws -> String {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any]
        else {
            await trace(
                .decodeFailed,
                "Failed to extract provider response content envelope.",
                payload: String(decoding: data, as: UTF8.self)
            )
            throw AIServiceError.parsingFailed
        }

        if let content = message["content"] as? String {
            await trace(
                .responseContentExtracted,
                "Extracted string response content.",
                metadata: ["content_length": String(content.count)],
                payload: content
            )
            return content
        }

        if let contentParts = message["content"] as? [[String: Any]] {
            let text = contentParts.compactMap { part -> String? in
                if let text = part["text"] as? String { return text }
                return nil
            }
            .joined(separator: "\n")

            if !text.isEmpty {
                await trace(
                    .responseContentExtracted,
                    "Extracted multipart response content.",
                    metadata: ["content_length": String(text.count)],
                    payload: text
                )
                return text
            }
        }

        await trace(
            .decodeFailed,
            "Provider response content was empty after extraction.",
            payload: String(decoding: data, as: UTF8.self)
        )
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

    func apiErrorCode(from data: Data) -> String? {
        if
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? [String: Any],
            let code = error["code"] as? String
        {
            return code
        }

        return nil
    }

    func decodeGeneratedCards(
        from jsonString: String,
        contract: AIGeneratedCardContract
    ) async throws -> [AIFlashcard] {
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
            await trace(
                .decodeFailed,
                "Failed to materialize cleaned generated-card JSON as UTF-8 data.",
                metadata: ["contract": String(describing: contract)],
                payload: clean
            )
            throw AIServiceError.parsingFailed
        }

        await trace(
            .decodePrepared,
            "Prepared generated-card JSON for decoding.",
            metadata: [
                "contract": String(describing: contract),
                "clean_json_length": String(clean.count)
            ],
            payload: clean
        )

        do {
            let dto = try JSONDecoder().decode(DeckJSONCardBatchDTO.self, from: data)
            guard dto.schemaVersion == DeckJSONDocument.supportedSchemaVersion, !dto.cards.isEmpty else {
                throw AIServiceError.parsingFailed
            }
            let decodedCards = try dto.cards.map { try aiFlashcard(from: $0, expectedContract: contract) }

            await trace(
                .decodeSucceeded,
                "Decoded generated cards successfully.",
                metadata: [
                    "contract": String(describing: contract),
                    "decoded_count": String(decodedCards.count)
                ]
            )
            return decodedCards
        } catch {
            await trace(
                .decodeFailed,
                "Generated-card decoding failed.",
                metadata: [
                    "contract": String(describing: contract),
                    "error": String(describing: error)
                ],
                payload: clean
            )
            throw AIServiceError.parsingFailed
        }
    }

    func aiFlashcard(
        from card: DeckJSONCardDTO,
        expectedContract: AIGeneratedCardContract
    ) throws -> AIFlashcard {
        switch (expectedContract, card) {
        case (.flashcard, .flashcard(let payload)):
            let questionZones = sanitizedZoneStrings(aiZoneStrings(from: payload.front))
            let answerZones = sanitizedZoneStrings(aiZoneStrings(from: payload.back))
            guard !questionZones.isEmpty, !answerZones.isEmpty else {
                throw AIServiceError.parsingFailed
            }

            return AIFlashcard(
                id: UUID(),
                content: .flashcard(
                    AIFlashcardContent(
                        questionZones: questionZones,
                        answerZones: answerZones
                    )
                )
            )
        case (.quiz, .quiz(let payload)):
            let questionZones = sanitizedZoneStrings(aiZoneStrings(from: payload.question))
            let normalizedChoices = payload.choices.compactMap { choice -> (text: String, isCorrect: Bool)? in
                let text = sanitizedZoneStrings(aiZoneStrings(from: DeckJSONCardFaceDTO(zones: choice.zones)))
                    .joined(separator: AIZoneParser.zoneDelimiter)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return (text, choice.isCorrect)
            }
            let choices = normalizedChoices.map(\.text)
            let correctIndexes = normalizedChoices.enumerated().compactMap { index, choice in
                choice.isCorrect ? index : nil
            }
            let explanationZones = payload.explanation.map { sanitizedZoneStrings(aiZoneStrings(from: $0)) } ?? []

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
        default:
            throw AIServiceError.parsingFailed
        }
    }

    func aiZoneStrings(from face: DeckJSONCardFaceDTO) -> [String] {
        face.zones.flatMap(aiZoneStrings(from:))
    }

    func aiZoneStrings(from zone: DeckJSONZoneDTO) -> [String] {
        if let children = zone.children, !children.isEmpty {
            return children.flatMap(aiZoneStrings(from:))
        }

        switch zone.type {
        case .text:
            return [zone.text ?? ""]
        case .code:
            return [codeZoneString(from: zone)]
        case .empty, .image, .sketch, .container:
            return []
        }
    }

    func sanitizedZoneStrings(_ values: [String]) -> [String] {
        values
            .map { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return isFencedCodeBlock(trimmed) ? trimmed : AIZoneParser.sanitizeLatex(trimmed)
            }
            .filter { !$0.isEmpty }
    }

    func codeZoneString(from zone: DeckJSONZoneDTO) -> String {
        let text = zone.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !isFencedCodeBlock(text) else { return text }

        return "```\n\(text)\n```"
    }

    func isFencedCodeBlock(_ value: String) -> Bool {
        value.hasPrefix("```") && value.hasSuffix("```")
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
