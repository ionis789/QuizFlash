import Foundation
import UIKit
import SwiftData

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
        [
            ["role": "system", "content": systemPrompt(targetCards: targetCards, isOCR: needsOCRCorrection, options: options)],
            ["role": "user", "content": buildTextUserMessage(
                text: text,
                targetCards: targetCards,
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

    nonisolated func buildConversionMessages(
        sourceCards: [AICardConversionSource],
        targetType: AICardGenerationType,
        level: AICardGenerationLevel
    ) -> [[String: Any]] {
        [
            [
                "role": "system",
                "content": conversionSystemPrompt(
                    sourceCount: sourceCards.count,
                    targetType: targetType,
                    level: level
                )
            ],
            [
                "role": "user",
                "content": conversionUserMessage(
                    sourceCards: sourceCards,
                    targetType: targetType
                )
            ]
        ]
    }

    nonisolated func buildTextUserMessage(
        text: String,
        targetCards: Int,
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
        - Generate EXACTLY \(targetCards) cards from this source segment only.
        - Focus on distinct concepts from this segment. Avoid vague overview cards.
        - Avoid repeating the same wording or concept inside this batch.
        """

        if passIndex > 1 {
            message += "\n- This source has already been used before. Cover NEW concepts or a noticeably different angle."
        }

        if !coveredPrompts.isEmpty {
            message += "\n- Avoid overlapping these already-covered prompts when possible:"
            for covered in coveredPrompts.prefix(6) {
                message += "\n  • \(covered)"
            }
        }

        message += "\n\nSOURCE TEXT:\n\n\(text)"
        return message
    }

    nonisolated func buildVisionUserMessage(
        targetCards: Int,
        sourceLabel: String,
        batchIndex: Int,
        totalBatches: Int,
        passIndex: Int,
        coveredPrompts: [String]
    ) -> String {
        var message = """
        Analyze only the attached source pages/images and generate EXACTLY \(targetCards) cards.
        Batch \(batchIndex) of \(totalBatches).
        Source coverage: \(sourceLabel).
        Focus on distinct concepts from these specific pages/images.
        """

        if passIndex > 1 {
            message += "\nThis source group has already been used in an earlier pass. Cover new concepts or a clearly different angle."
        }

        if !coveredPrompts.isEmpty {
            message += "\nAvoid overlapping these already-covered prompts when possible:"
            for covered in coveredPrompts.prefix(6) {
                message += "\n- \(covered)"
            }
        }

        return message
    }

    nonisolated func conversionUserMessage(
        sourceCards: [AICardConversionSource],
        targetType: AICardGenerationType
    ) -> String {
        let body = sourceCards.enumerated().map { index, card in
            """
            SOURCE_INDEX: \(index)
            SOURCE_KIND: \(card.kind.rawValue)
            SOURCE_CARD:
            \(conversionSourceBody(for: card.content))
            """
        }
        .joined(separator: "\n\n---\n\n")

        if targetType == .match {
            return """
            Convert each source card below into ONE \(targetType.title) output.
            Preserve the dominant language of each source card.
            Keep the order stable and return one result for every SOURCE_INDEX.

            CRITICAL FOR MATCH:
            - Do NOT mechanically paraphrase the whole front/back pair.
            - Extract the single best atomic cue -> counterpart pair from each source card.
            - Keep the pairing style consistent across this batch whenever possible.
            - Prefer canonical study pairs such as concept -> definition, notation -> meaning, rule name -> rule statement, symbol -> interpretation.
            - If the source card is broad, choose the most concrete sub-concept that still teaches something useful.
            - The answer must be the direct counterpart, not an explanation, proof sketch, or mini flashcard back.

            SOURCE CARDS:

            \(body)
            """
        }

        return """
        Convert each source card below into ONE \(targetType.title) output.
        Preserve the dominant language of each source card.
        Keep the order stable and return one result for every SOURCE_INDEX.

        SOURCE CARDS:

        \(body)
        """
    }

    // =========================================================================
    // MARK: - System Prompt
    // =========================================================================
    //
    // DESIGN PRINCIPLES:
    //   • AI returns zones as string arrays, not a single block of text
    //   • Each array element = one visual zone block in the app
    //   • Clear splitting rules: when to use 1 zone vs multiple
    //   • Explicit LaTeX escaping rules with CONCRETE before/after examples
    //   • Math always in $...$ or $$...$$, never raw
    //   • The LaTeX escaping section uses a concrete "LOOK AT THIS OUTPUT"
    //     style to prevent GPT from over-thinking the escaping.
    //
    // =========================================================================

    nonisolated func systemPrompt(
        targetCards: Int,
        isOCR: Bool,
        options: AIGenerationOptions
    ) -> String {
        let outputContract = options.cardType.outputContract
        var prompt = #"""
        You are a rigorous University Professor AI specialized in generating elite, in-depth "Active Recall" flashcards.
        Your absolute priority is TECHNICAL DEPTH, ACCURACY, and HIGH READABILITY.
        
        Output STRICTLY valid JSON with EXACTLY \#(targetCards) cards.
        
        ═══════════════════════════════════════════════════════
        LANGUAGE RULE (CRITICAL)
        ═══════════════════════════════════════════════════════
        You MUST EXACTLY match the language of the source text. If the source text is in language X, the flashcards MUST be written in language X. Do not translate concepts to English.
        Detect the dominant language from the actual teaching material before writing.
        NEVER mix languages across cards unless the source itself explicitly mixes them.
        NEVER default to English because of model preference or technical terminology.
        If the source is X language, the flashcards MUST be fully in X language.
        
        ═══════════════════════════════════════════════════════
        LATEX ESCAPING IN JSON — READ THIS VERY CAREFULLY
        ═══════════════════════════════════════════════════════
        You are writing JSON. JSON strings use backslash (\) as an escape character.
        Therefore, to produce ONE backslash in the final text, you must write TWO backslashes in the JSON.
        
        THE RULE IS SIMPLE:
          Every LaTeX command that starts with one backslash must be written with EXACTLY two backslashes in your JSON output.
        
        COPY THESE EXAMPLES EXACTLY — do not add more backslashes:
        
          LaTeX you want   →   What you write in the JSON string
          ─────────────────────────────────────────────────────
          \lambda          →   \\lambda
          \frac{a}{b}      →   \\frac{a}{b}
          \in              →   \\in
          \mathbb{R}       →   \\mathbb{R}
          \forall          →   \\forall
          \sum_{i=1}^{n}   →   \\sum_{i=1}^{n}
          \begin{pmatrix}  →   \\begin{pmatrix}
          \end{pmatrix}    →   \\end{pmatrix}
          \text{some text} →   \\text{some text}
        
        ❌ WRONG (under-escaped — JSON will break):
          "answer_zones": ["$\lambda + \mu$"]
        
        ❌ WRONG (over-escaped — LaTeX will break):
          "answer_zones": ["$\\\\lambda + \\\\mu$"]
        
        ✅ CORRECT:
          "answer_zones": ["$\\lambda + \\mu$"]
        
        NEVER write four backslashes (\\\\) before a LaTeX command. Always exactly two (\\).
        """#

        prompt += requiredJSONSchemaPrompt(for: outputContract)
        prompt += formattingRulesPrompt(for: outputContract)

        if isOCR {
            prompt += """
        
        ═══════════════════════════════════════════════════════
        OCR CORRECTION MODE ENABLED
        ═══════════════════════════════════════════════════════
        Repair corrupted code syntax, broken LaTeX, and misrecognized symbols (e.g., 0/O, 1/l, alpha/a). Preserve strict technical correctness.
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

        ═══════════════════════════════════════════════════════
        REQUIRED JSON SCHEMA (CRITICAL - DO NOT ALTER)
        ═══════════════════════════════════════════════════════
        You MUST output valid JSON matching EXACTLY this schema:
        {
          "cards": [
            {
              "question_zones": ["string1", "string2"],
              "answer_zones": ["string1", "string2", "string3"]
            }
          ]
        }
        STRICT RULE: NEVER use the key "question" or "answer".
        You MUST use EXACTLY "question_zones" and "answer_zones" as ARRAYS of strings.
        """
        case .match:
            return """

        ═══════════════════════════════════════════════════════
        REQUIRED JSON SCHEMA (CRITICAL - DO NOT ALTER)
        ═══════════════════════════════════════════════════════
        You MUST output valid JSON matching EXACTLY this schema:
        {
          "cards": [
            {
              "prompt": "string",
              "answer": "string"
            }
          ]
        }
        STRICT RULES:
        - "prompt" MUST be one short plain string, not an array.
        - "answer" MUST be one short plain string, not an array.
        - Keep both values compact enough to stay readable in a small matching tile.
        - Do not add explanations, numbering, prefixes, or extra commentary.
        """
        case .quiz:
            return """

        ═══════════════════════════════════════════════════════
        REQUIRED JSON SCHEMA (CRITICAL - DO NOT ALTER)
        ═══════════════════════════════════════════════════════
        You MUST output valid JSON matching EXACTLY this schema:
        {
          "cards": [
            {
              "question_zones": ["string1", "string2"],
              "choices": ["choice 1", "choice 2", "choice 3", "choice 4"],
              "correct_indexes": [1],
              "explanation_zones": ["string1", "string2"]
            }
          ]
        }
        STRICT RULES:
        - "question_zones" MUST be an array of strings.
        - "choices" MUST be an array of answer-choice strings.
        - "correct_indexes" MUST be zero-based indexes into the "choices" array.
        - "correct_indexes" may contain more than one index when multiple answers are correct.
        - "explanation_zones" is optional, but if present it MUST be an array of strings.
        """
        case .write:
            return """

        ═══════════════════════════════════════════════════════
        REQUIRED JSON SCHEMA (CRITICAL - DO NOT ALTER)
        ═══════════════════════════════════════════════════════
        You MUST output valid JSON matching EXACTLY this schema:
        {
          "cards": [
            {
              "source_text": "string",
              "omitted_text": "string"
            }
          ]
        }
        STRICT RULES:
        - "source_text" MUST be one plain string, not an array.
        - "omitted_text" MUST be the exact substring removed from source_text.
        - source_text MUST contain omitted_text exactly once, verbatim.
        """
        }
    }

    nonisolated func formattingRulesPrompt(for contract: AIGeneratedCardContract) -> String {
        switch contract {
        case .flashcard, .quiz:
            return """

        ═══════════════════════════════════════════════════════
        ZONE SPLITTING & READABILITY
        ═══════════════════════════════════════════════════════
        You MUST break long content into multiple readable, atomic visual zones using the JSON arrays.
        Do not create "walls of text". Instead of cramming everything into one long string, split the information logically into as many zones as needed:

        RULE: Code MUST ALWAYS be in its own standalone string.
        RULE: Block equations ($$) MUST ALWAYS be in their own standalone string.

        ❌ BAD EXAMPLE (Wall of text, mixed code - DO NOT DO THIS):
        "answer_zones": [
          "The Singleton pattern restricts instantiation. Here is the code: public class Singleton { private static Singleton instance; }"
        ]

        ✅ GOOD EXAMPLE (Split into logical, readable zones - DO THIS EXACTLY):
        "answer_zones": [
          "The **Singleton** pattern restricts instantiation by using a private constructor.",
          "The instance is created lazily, meaning it is only instantiated when first requested.",
          "```java\npublic class Singleton {\n    private static Singleton instance;\n    private Singleton() {}\n}\n```"
        ]

        ═══════════════════════════════════════════════════════
        FORMATTING RULES (STRICT)
        ═══════════════════════════════════════════════════════
        - TEXT HIGHLIGHTS: Highlight all crucial concepts using double asterisks (e.g., "**Encapsulation**").
        - INLINE CODE: Use single backticks (`) for short syntax, class names, or technical terms (e.g., `new`, `String`).
        - INLINE MATH: Wrap every math symbol, variable, and inline equation in single $. Example: "$v \\in V$", "$\\dim(V)$".
        - BLOCK MATH: Wrap display equations in double $$. NEVER use ```math or ```latex fences for equations.
        - BLOCK CODE: Triple-backtick code blocks MUST be in their own standalone string in the array.
        """
        case .write:
            return """

        ═══════════════════════════════════════════════════════
        FORMATTING RULES (STRICT)
        ═══════════════════════════════════════════════════════
        - TEXT HIGHLIGHTS: Highlight crucial concepts using double asterisks only when it improves recall.
        - INLINE CODE: Use single backticks (`) for short syntax, class names, or technical terms.
        - INLINE MATH: Wrap every math symbol, variable, and inline equation in single $.
        - BLOCK MATH: Wrap display equations in double $$ when needed.
        - source_text should stay compact enough for a single fill-in-the-blank prompt.
        - omitted_text should be the shortest exact answer span that still preserves a meaningful recall task.
        """
        case .match:
            return """

        ═══════════════════════════════════════════════════════
        FORMATTING RULES (STRICT)
        ═══════════════════════════════════════════════════════
        - prompt and answer MUST stay plain, compact, and immediately scannable.
        - Prefer a single line for each field. Avoid bullet points, numbering, and sentence fragments stacked across lines.
        - Think in compact pairs only: term -> definition, notation -> meaning, event -> outcome, structure -> property.
        - Within one batch, prefer ONE stable pairing style instead of mixing unrelated pair types.
        - The pair should feel like a direct textbook counterpart, not like two vaguely related study notes.
        - The answer must uniquely resolve the prompt among neighboring cards in the same batch.
        - Each field should feel readable in under one second.
        - Avoid markdown emphasis unless a math or code symbol is essential to the concept.
        - Never include explanations, examples, or qualifiers beyond the direct pair itself.
        - Never output lists, semicolon chains, or mini paragraphs.
        - Avoid generic answers that could match many prompts in the same deck.
        - If the source concept is too broad for a compact pair, skip it and generate a tighter concept instead.
        """
        }
    }

    nonisolated func deckTitleSystemPrompt() -> String {
        #"""
        You are a precise academic assistant that creates short deck titles.

        Output STRICTLY valid JSON matching EXACTLY this schema:
        {
          "deck_title": "string"
        }

        RULES:
        - The title MUST be in the same dominant language as the source text.
        - Never translate the title to English unless the source is actually in English.
        - Keep it short: ideally 2 to 5 words.
        - Make it specific to the topic, not generic.
        - Do not add quotes, emojis, subtitles, colons, or extra commentary.
        - Return ONLY the JSON object.
        """#
    }

    nonisolated func deckTitleUserMessage(fromText text: String) -> String {
        """
        Read the sampled source text below and infer a short deck title.

        SAMPLE SOURCE:
        \(text)
        """
    }

    nonisolated func conversionSystemPrompt(
        sourceCount: Int,
        targetType: AICardGenerationType,
        level: AICardGenerationLevel
    ) -> String {
        var prompt = """
        You are a rigorous study-card conversion engine.
        Convert existing cards into a new target format without inventing unsupported facts.

        Output STRICTLY valid JSON with EXACTLY \(sourceCount) results.

        ═══════════════════════════════════════════════════════
        CONVERSION RULES (CRITICAL)
        ═══════════════════════════════════════════════════════
        - Preserve the dominant language of each source card.
        - Each result MUST map to one source card via its exact source_index.
        - Keep the semantic core intact, but adapt the phrasing to the target card format.
        - Do not merge multiple source cards into one output.
        - Do not omit any source_index.
        - When a source is verbose, compress it into the smallest faithful target representation.
        - Do not add meta commentary such as "converted card", "answer", "prompt", or numbering inside the generated fields.

        ═══════════════════════════════════════════════════════
        LATEX ESCAPING IN JSON
        ═══════════════════════════════════════════════════════
        Every LaTeX command that starts with one backslash must be written with EXACTLY two backslashes in the JSON string.
        Example: \\lambda in the final card must appear as \\\\lambda in the JSON output.
        Never write four backslashes before a LaTeX command.
        """

        prompt += requiredConversionSchemaPrompt(for: targetType.outputContract)
        prompt += formattingRulesPrompt(for: targetType.outputContract)
        prompt += cardTypePromptAddition(for: targetType)
        prompt += cardLevelPromptAddition(for: level)

        return prompt
    }

    nonisolated func requiredConversionSchemaPrompt(for contract: AIGeneratedCardContract) -> String {
        switch contract {
        case .flashcard:
            return """

        ═══════════════════════════════════════════════════════
        REQUIRED JSON SCHEMA (CRITICAL - DO NOT ALTER)
        ═══════════════════════════════════════════════════════
        {
          "results": [
            {
              "source_index": 0,
              "question_zones": ["string1", "string2"],
              "answer_zones": ["string1", "string2"]
            }
          ]
        }
        STRICT RULES:
        - "results" MUST contain EXACTLY one object per source card.
        - "source_index" MUST exactly match the source card index provided in the prompt.
        - "question_zones" and "answer_zones" MUST be arrays of strings.
        """
        case .match:
            return """

        ═══════════════════════════════════════════════════════
        REQUIRED JSON SCHEMA (CRITICAL - DO NOT ALTER)
        ═══════════════════════════════════════════════════════
        {
          "results": [
            {
              "source_index": 0,
              "prompt": "string",
              "answer": "string"
            }
          ]
        }
        STRICT RULES:
        - "results" MUST contain EXACTLY one object per source card.
        - "source_index" MUST exactly match the source card index provided in the prompt.
        - "prompt" and "answer" MUST be short plain strings.
        """
        case .quiz:
            return """

        ═══════════════════════════════════════════════════════
        REQUIRED JSON SCHEMA (CRITICAL - DO NOT ALTER)
        ═══════════════════════════════════════════════════════
        {
          "results": [
            {
              "source_index": 0,
              "question_zones": ["string1", "string2"],
              "choices": ["choice 1", "choice 2", "choice 3", "choice 4"],
              "correct_indexes": [1],
              "explanation_zones": ["string1"]
            }
          ]
        }
        STRICT RULES:
        - "results" MUST contain EXACTLY one object per source card.
        - "source_index" MUST exactly match the source card index provided in the prompt.
        - "correct_indexes" MUST be zero-based indexes into "choices".
        - "choices" MUST contain at least four plausible options.
        """
        case .write:
            return """

        ═══════════════════════════════════════════════════════
        REQUIRED JSON SCHEMA (CRITICAL - DO NOT ALTER)
        ═══════════════════════════════════════════════════════
        {
          "results": [
            {
              "source_index": 0,
              "source_text": "string",
              "omitted_text": "string"
            }
          ]
        }
        STRICT RULES:
        - "results" MUST contain EXACTLY one object per source card.
        - "source_index" MUST exactly match the source card index provided in the prompt.
        - "source_text" MUST contain "omitted_text" exactly once, verbatim.
        """
        }
    }

    nonisolated func cardTypePromptAddition(for type: AICardGenerationType) -> String {
        switch type {
        case .flashcards:
            return """

        ═══════════════════════════════════════════════════════
        CARD TYPE PROFILE — FLASH CARDS
        ═══════════════════════════════════════════════════════
        Generate classic active-recall cards with a strong question on the front and a high-signal answer on the back.
        Prefer one core concept, mechanism, theorem, or tightly related cluster per card.
        """
        case .match:
            return """

        ═══════════════════════════════════════════════════════
        CARD TYPE PROFILE — MATCH CARDS
        ═══════════════════════════════════════════════════════
        These cards must remain easy to pair in match mode.
        The front should usually be a short term, concept label, notation, rule name, formula name, symbol, or compact cue.
        The back should be the direct counterpart only: concise definition, interpretation, named result, canonical statement, or exact mapping.
        Prefer the tightest faithful pair, not the most complete explanation.
        Keep the relation family consistent across the batch whenever possible.
        Good examples of relation families:
        - concept -> definition
        - notation -> meaning
        - symbol -> interpretation
        - rule/theorem name -> formal statement
        - structure -> defining property
        Avoid mixing formula-name cards, notation cards, and definition cards randomly unless the source strongly demands it.
        If the source is phrased as a long question, extract the underlying concept name or notation instead of copying the whole question style.
        If the source answer contains several clauses, keep only the single canonical counterpart that best teaches the concept.
        Use formulas as answers only when the source concept is itself a named rule/schema and the formula is the canonical statement of that rule.
        Do not turn one source concept into a mini flashcard answer. Match needs compact canonical pairs, not explanations.
        Skip broad concepts that would require multiple clauses to explain.
        """
        case .quiz:
            return """

        ═══════════════════════════════════════════════════════
        CARD TYPE PROFILE — QUIZ CARDS
        ═══════════════════════════════════════════════════════
        Each card must behave like a multiple-choice quiz item.
        question_zones should contain the quiz stem and any short setup needed to understand it.
        choices MUST contain at least four plausible options.
        correct_indexes MUST point to the exact correct options in the choices array.
        Multiple correct answers are allowed when the source truly supports that.
        explanation_zones, when present, should briefly justify the correct answer(s) without repeating the full stem.
        """
        case .write:
            return """

        ═══════════════════════════════════════════════════════
        CARD TYPE PROFILE — WRITE CARDS
        ═══════════════════════════════════════════════════════
        These cards are intended for typed recall.
        source_text MUST read like the final prompt shown to the learner before blanking.
        omitted_text MUST be the exact phrase, symbol sequence, definition term, formula fragment, or short structured answer the learner should type.
        Prefer one omission only.
        The omitted_text must appear exactly once inside source_text.
        """
        }
    }

    nonisolated func cardLevelPromptAddition(for level: AICardGenerationLevel) -> String {
        switch level {
        case .simple:
            return """

        ═══════════════════════════════════════════════════════
        CARD LEVEL PROFILE — SIMPLE
        ═══════════════════════════════════════════════════════
        Keep the wording accessible and direct.
        Focus on the clearest core facts, definitions, and cause-effect relations.
        Avoid overly layered answers unless absolutely necessary.
        """
        case .balanced:
            return """

        ═══════════════════════════════════════════════════════
        CARD LEVEL PROFILE — BALANCED
        ═══════════════════════════════════════════════════════
        Keep the current prompt style balance: clear, technically correct, and moderately detailed.
        """
        case .advanced:
            return """

        ═══════════════════════════════════════════════════════
        CARD LEVEL PROFILE — ADVANCED
        ═══════════════════════════════════════════════════════
        Prefer deeper reasoning, nuance, caveats, mechanisms, proofs, and higher-order distinctions whenever the source supports them.
        Questions should test understanding, not just memorized wording.
        """
        }
    }

    // -------------------------------------------------------------------------
}
