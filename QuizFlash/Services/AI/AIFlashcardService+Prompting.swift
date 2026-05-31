import Foundation
import UIKit

extension AIFlashcardService {
    nonisolated func buildTextMessages(
        text: String,
        targetCards: Int,
        needsOCRCorrection: Bool,
        options: AIGenerationOptions,
        sourceLabel: String,
        batchIndex: Int,
        totalBatches: Int,
        passIndex: Int,
        coveredPrompts: [String]
    ) -> [[String: Any]] {
        let preparedText = preparedSourceTextForPrompt(
            text,
            cardType: options.cardType,
            needsOCRCorrection: needsOCRCorrection,
            targetCards: targetCards
        )
        return [
            ["role": "system", "content": systemPrompt(targetCards: targetCards, isOCR: needsOCRCorrection, options: options)],
            ["role": "user", "content": buildTextUserMessage(
                text: preparedText,
                targetCards: targetCards,
                options: options,
                cardType: options.cardType,
                sourceLabel: sourceLabel,
                batchIndex: batchIndex,
                totalBatches: totalBatches,
                passIndex: passIndex,
                coveredPrompts: coveredPrompts
            )]
        ]
    }

    nonisolated func buildVisionMessages(
        images: [UIImage],
        targetCards: Int,
        options: AIGenerationOptions,
        sourceLabel: String,
        batchIndex: Int,
        totalBatches: Int,
        passIndex: Int,
        coveredPrompts: [String]
    ) -> [[String: Any]] {
        var userContent: [[String: Any]] = [
            ["type": "text", "text": buildVisionUserMessage(
                targetCards: targetCards,
                options: options,
                cardType: options.cardType,
                sourceLabel: sourceLabel,
                batchIndex: batchIndex,
                totalBatches: totalBatches,
                passIndex: passIndex,
                coveredPrompts: coveredPrompts
            )]
        ]
        for image in images {
            guard let data = image.jpegData(compressionQuality: 0.7) else { continue }
            userContent.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())", "detail": "auto"]
            ])
        }
        return [
            ["role": "system", "content": systemPrompt(targetCards: targetCards, isOCR: false, options: options)],
            ["role": "user", "content": userContent]
        ]
    }

    nonisolated func buildDeckTitleMessages(fromText text: String) -> [[String: Any]] {
        [
            ["role": "system", "content": deckTitleSystemPrompt()],
            ["role": "user", "content": deckTitleUserMessage(fromText: text)]
        ]
    }

    nonisolated func buildTextUserMessage(
        text: String,
        targetCards: Int,
        options: AIGenerationOptions,
        cardType: AICardGenerationType,
        sourceLabel: String,
        batchIndex: Int,
        totalBatches: Int,
        passIndex: Int,
        coveredPrompts: [String]
    ) -> String {
        var message = """
        GENERATION CONTEXT
        - Batch \(batchIndex) of \(totalBatches)
        - Source coverage: \(sourceLabel)
        - Generate EXACTLY \(targetCards) \(cardType.title) from this source segment only.
        - Focus on distinct concepts from this segment.
        - Avoid vague overview cards and repeated wording.
        """

        if let languageHint = options.sourceLanguageHint {
            message += "\n- The output language is locked to \(languageHint.displayName) (\(languageHint.languageCode)). Keep every card fully in that language."
        }

        if passIndex > 1 {
            message += "\n- This source has already been used before. Cover new concepts or a clearly different angle."
        }

        if cardType == .flashcards {
            message += "\n- Build atomic active-recall cards with one crisp recall task per card."
            message += "\n- Keep front zones short and direct."
            message += "\n- Keep back zones high-signal and sized to the selected depth."
        } else {
            message += "\n- Build multiple-choice quiz cards with plausible choices and explicit isCorrect flags."
            message += "\n- Use explanations only when they clarify why the answer is correct."
        }

        if !coveredPrompts.isEmpty {
            message += "\n- Avoid overlapping these already-covered prompts when possible:"
            for covered in coveredPrompts.prefix(4) {
                message += "\n  - \(covered)"
            }
        }

        message += "\n\nSOURCE TEXT:\n\n\(text)"
        return message
    }

    nonisolated func buildVisionUserMessage(
        targetCards: Int,
        options: AIGenerationOptions,
        cardType: AICardGenerationType,
        sourceLabel: String,
        batchIndex: Int,
        totalBatches: Int,
        passIndex: Int,
        coveredPrompts: [String]
    ) -> String {
        var message = """
        Analyze only the attached source pages/images and generate EXACTLY \(targetCards) \(cardType.title).
        Batch \(batchIndex) of \(totalBatches).
        Source coverage: \(sourceLabel).
        Focus on distinct concepts from these specific pages/images.
        """

        if let languageHint = options.sourceLanguageHint {
            message += "\nThe output language is locked to \(languageHint.displayName) (\(languageHint.languageCode)). Keep every card fully in that language."
        }

        if passIndex > 1 {
            message += "\nThis source group has already been used in an earlier pass. Cover new concepts or a clearly different angle."
        }

        if cardType == .flashcards {
            message += "\nBuild atomic active-recall cards, not mini essays."
        } else {
            message += "\nBuild multiple-choice quiz cards with plausible distractors and valid zero-based correct indexes."
        }

        if !coveredPrompts.isEmpty {
            message += "\nAvoid overlapping these already-covered prompts when possible:"
            for covered in coveredPrompts.prefix(4) {
                message += "\n- \(covered)"
            }
        }

        return message
    }

    nonisolated func systemPrompt(
        targetCards: Int,
        isOCR: Bool,
        options: AIGenerationOptions
    ) -> String {
        let outputContract = options.cardType.outputContract
        var prompt = """
        You generate rigorous study content for QuizFlash.
        Your absolute priorities are technical accuracy, compact mobile readability, and faithful notation.
        Output STRICTLY valid JSON using the canonical QuizFlash card DTO with EXACTLY \(targetCards) cards.
        Generate only the requested card type: \(options.cardType.title).
        Do not generate deck metadata, ids, dates, image zones, or sketch zones.

        \(languageRulePrompt(for: options))

        LATEX IN JSON
        Every math symbol, variable, and inline equation MUST be inside a single balanced $...$ block.
        Display equations MUST be inside a balanced $$...$$ block and must be placed in their own standalone text zone.
        Never output raw math notation such as a_{i}, x^2, 0_W, \\cdot, \\lambda, \\mathbb{R}, ∀, ∈, ⇔, →, ≤, ≥, or ≠ outside math delimiters.
        Every LaTeX command that starts with one backslash must be written with EXACTLY two backslashes in JSON.
        Example final card text "$v \\in V$" must appear in JSON as "$v \\\\in V$".
        Never write four backslashes before a LaTeX command.
        """

        prompt += requiredJSONSchemaPrompt(for: outputContract)
        prompt += formattingRulesPrompt(for: outputContract)
        prompt += mobileCardLayoutPrompt(for: outputContract)

        if isOCR {
            prompt += """

            OCR CORRECTION MODE ENABLED
            Repair broken words, split hyphenations, noisy symbols, damaged code syntax, and corrupted notation before generating cards.
            """
        }

        prompt += cardTypePromptAddition(for: options.cardType)
        prompt += cardLevelPromptAddition(for: options.cardLevel)
        return prompt
    }

    nonisolated func requiredJSONSchemaPrompt(for contract: AIGeneratedCardContract) -> String {
        switch contract {
        case .flashcard:
            return """

            REQUIRED JSON SCHEMA
            {
              "schemaVersion": 1,
              "cards": [
                {
                  "type": "flashcard",
                  "front": {
                    "zones": [
                      { "type": "text", "text": "short prompt" }
                    ]
                  },
                  "back": {
                    "zones": [
                      { "type": "text", "text": "answer detail" }
                    ]
                  }
                }
              ]
            }
            Use only "text", "code", and "container" zone types. A container zone must include "children".
            """
        case .quiz:
            return """

            REQUIRED JSON SCHEMA
            {
              "schemaVersion": 1,
              "cards": [
                {
                  "type": "quiz",
                  "question": {
                    "zones": [
                      { "type": "text", "text": "question" }
                    ]
                  },
                  "choices": [
                    {
                      "zones": [
                        { "type": "text", "text": "choice 1" }
                      ],
                      "isCorrect": true
                    },
                    {
                      "zones": [
                        { "type": "text", "text": "choice 2" }
                      ],
                      "isCorrect": false
                    }
                  ],
                  "explanation": {
                    "zones": [
                      { "type": "text", "text": "why the answer is correct" }
                    ]
                  }
                }
              ]
            }
            Use only "text", "code", and "container" zone types. Each quiz must have at least two choices and at least one choice with "isCorrect": true.
            "explanation" is optional.
            """
        }
    }

    nonisolated func formattingRulesPrompt(for contract: AIGeneratedCardContract) -> String {
        switch contract {
        case .flashcard:
            return """

            FLASHCARD RULES
            - Prefer one atomic recall target per card.
            - Keep prompts concise and direct.
            - Split long answers into small visual zones.
            - Use code blocks or display equations only when they materially teach the concept.
            - Avoid list dumps and repeated paraphrases.
            - INLINE MATH: Wrap every math symbol, variable, and inline equation in single $.
            - BLOCK MATH: Wrap display equations in double $$ only when the equation itself is important.
            - Put long block equations in their own standalone text zone using $$...$$.
            - Do not leave raw notation like a_{i}, x^2, 0_W, \\cdot, \\lambda, ∀, ∈, ⇔, →, or ℝ outside math delimiters.
            - Keep ordinary Romanian/Russian/English prose outside math delimiters.
            """
        case .quiz:
            return """

            QUIZ RULES
            - Ask one clear question per card.
            - Provide at least 3 plausible choices when the source supports them.
            - Include one or more correct indexes when multiple answers are correct.
            - Keep distractors plausible but unambiguously wrong.
            - Add a concise explanation when it helps learning.
            - INLINE MATH: Wrap every math symbol, variable, and inline equation in single $.
            - BLOCK MATH: Wrap display equations in double $$. NEVER use ```math or ```latex fences for equations.
            - Put long block equations in their own standalone text zone using $$...$$.
            - Do not leave raw notation like a_{i}, x^2, 0_W, \\cdot, \\lambda, ∀, ∈, ⇔, →, or ℝ outside math delimiters.
            - Keep ordinary Romanian/Russian/English prose outside math delimiters.
            """
        }
    }

    nonisolated func mobileCardLayoutPrompt(for contract: AIGeneratedCardContract) -> String {
        switch contract {
        case .flashcard:
            return """

            MOBILE LAYOUT
            Keep each question readable on a phone card. Keep answer zones scannable and avoid dense paragraphs.
            """
        case .quiz:
            return """

            MOBILE LAYOUT
            Keep the question and choices compact enough for a phone screen. Avoid choices that differ only by tiny wording.
            """
        }
    }

    nonisolated func deckTitleSystemPrompt() -> String {
        """
        You create short study deck titles.
        Return STRICT JSON only: {"deck_title":"..."}.
        Use the dominant language of the source.
        Keep the title under 6 words when possible.
        """
    }

    nonisolated func deckTitleUserMessage(fromText text: String) -> String {
        """
        Create one concise deck title for this source:

        \(String(text.prefix(6_000)))
        """
    }

    nonisolated func cardTypePromptAddition(for type: AICardGenerationType) -> String {
        switch type {
        case .flashcards:
            return """

            CARD TYPE: FLASHCARDS
            Create active-recall question/answer cards. Preserve exact technical terms, notation, formulas, and short code snippets when they are the best learning surface.
            """
        case .quiz:
            return """

            CARD TYPE: QUIZ
            Create multiple-choice questions that test understanding, not just keyword recognition. Keep choices parallel in shape and length when possible.
            """
        }
    }

    nonisolated func preparedSourceTextForPrompt(
        _ text: String,
        cardType: AICardGenerationType,
        needsOCRCorrection: Bool,
        targetCards: Int
    ) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharsPerChunk else { return trimmed }

        let prefixLimit = maxCharsPerChunk / 2
        let suffixLimit = maxCharsPerChunk - prefixLimit
        return """
        \(String(trimmed.prefix(prefixLimit)))

        [...source truncated for prompt budget...]

        \(String(trimmed.suffix(suffixLimit)))
        """
    }

    nonisolated func languageRulePrompt(for options: AIGenerationOptions) -> String {
        if let languageHint = options.sourceLanguageHint {
            return """
            LANGUAGE RULE
            Write every generated card in \(languageHint.displayName) (\(languageHint.languageCode)).
            Do not mix languages unless the source itself contains a quoted term, formula, code, or proper noun.
            """
        }

        return """
        LANGUAGE RULE
        Use the dominant natural language of the source text.
        Preserve quoted terms, formulas, code, and proper nouns exactly when needed.
        """
    }

    nonisolated func cardLevelPromptAddition(for level: AICardGenerationLevel) -> String {
        switch level {
        case .simple:
            return "\nDEPTH: Simple. Focus on core facts and definitions. Keep answers terse."
        case .balanced:
            return "\nDEPTH: Balanced. Cover core ideas with normal study depth."
        case .advanced:
            return "\nDEPTH: Advanced. Prefer nuanced, technical, higher-order understanding when the source supports it."
        }
    }
}
