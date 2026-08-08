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

    /// Providers sometimes write a LaTeX backslash without JSON-escaping it.
    ///
    /// This function runs on the raw JSON TEXT (before decoding) and ensures
    /// every LaTeX command has exactly two backslashes (\\command), so that
    /// after JSONDecoder the Swift String contains the correct single \command.
    ///
    /// Over-escaping (\\\\command → \\command) is handled POST-decode in
    /// AIZoneParser.fixOverescapedLatex(), which is simpler and safer there.
    func fixLatexEscaping(in jsonString: String) -> String {
        let characters = Array(jsonString)
        var result = ""
        result.reserveCapacity(jsonString.count)
        var isInsideJSONString = false
        var mathDelimiterLength = 0
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\\", isInsideJSONString {
                var runLength = 1
                while index + runLength < characters.count,
                      characters[index + runLength] == "\\" {
                    runLength += 1
                }
                let nextIndex = index + runLength
                let nextCharacter = nextIndex < characters.count ? characters[nextIndex] : nil
                let needsJSONEscape = mathDelimiterLength > 0 &&
                    !runLength.isMultiple(of: 2) &&
                    nextCharacter != nil &&
                    nextCharacter != "\""
                result.append(String(repeating: "\\", count: runLength + (needsJSONEscape ? 1 : 0)))

                if !runLength.isMultiple(of: 2), let nextCharacter {
                    result.append(nextCharacter)
                    index = nextIndex + 1
                } else {
                    index = nextIndex
                }
                continue
            }

            if character == "\"" {
                isInsideJSONString.toggle()
                if !isInsideJSONString { mathDelimiterLength = 0 }
                result.append(character)
                index += 1
                continue
            }

            if character == "$", isInsideJSONString {
                var runLength = 1
                while index + runLength < characters.count,
                      characters[index + runLength] == "$" {
                    runLength += 1
                }
                result.append(String(repeating: "$", count: runLength))
                if mathDelimiterLength == 0 {
                    mathDelimiterLength = min(runLength, 2)
                } else if runLength >= mathDelimiterLength {
                    mathDelimiterLength = 0
                }
                index += runLength
                continue
            }

            result.append(character)
            index += 1
        }

        return result
    }
}
