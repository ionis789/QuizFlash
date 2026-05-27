import Foundation
import UIKit
import SwiftData
import NaturalLanguage

nonisolated enum MatchSourceProfile: Sendable {
    case narrative
    case symbolic
    case code
    case academic
    case generic
}

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
        coveredPrompts: [String],
        approvedMatchExamples: [String] = [],
        matchOverlapHints: [String] = []
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
                coveredPrompts: coveredPrompts,
                approvedMatchExamples: approvedMatchExamples,
                matchOverlapHints: matchOverlapHints
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
        coveredPrompts: [String],
        approvedMatchExamples: [String] = [],
        matchOverlapHints: [String] = []
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
                coveredPrompts: coveredPrompts,
                approvedMatchExamples: approvedMatchExamples,
                matchOverlapHints: matchOverlapHints
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
        level: AICardGenerationLevel,
        targetCount: Int? = nil,
        approvedMatchExamples: [String] = [],
        matchOverlapHints: [String] = []
    ) -> [[String: Any]] {
        [
            [
                "role": "system",
                "content": conversionSystemPrompt(
                    sourceCount: sourceCards.count,
                    targetType: targetType,
                    level: level,
                    requestedResultCount: targetCount
                )
            ],
            [
                "role": "user",
                "content": conversionUserMessage(
                    sourceCards: sourceCards,
                    targetType: targetType,
                    targetCount: targetCount,
                    approvedMatchExamples: approvedMatchExamples,
                    matchOverlapHints: matchOverlapHints
                )
            ]
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
        coveredPrompts: [String],
        approvedMatchExamples: [String],
        matchOverlapHints: [String]
    ) -> String {
        let generationInstruction = cardType == .match
            ? "Generate UP TO \(targetCards) strong Match cards from this source segment only."
            : "Generate EXACTLY \(targetCards) cards from this source segment only."
        let sourceProfile = matchSourceProfile(for: text)

        var message = """
        GENERATION CONTEXT
        - Batch \(batchIndex) of \(totalBatches)
        - Source coverage: \(sourceLabel)
        - \(generationInstruction)
        - Focus on distinct concepts from this segment. Avoid vague overview cards.
        - Avoid repeating the same wording or concept inside this batch.
        """

        if let languageHint = options.sourceLanguageHint {
            message += "\n- The natural-language output for this run is locked to \(languageHint.displayName) (\(languageHint.languageCode)). Keep every card fully in that language."
        }

        if passIndex > 1 {
            message += "\n- This source has already been used before. Cover NEW concepts or a noticeably different angle."
        }

        if cardType == .match {
            message += "\n- Do not let the whole batch collapse into only label/name -> description cards."
            message += "\n- Favor game-worthy pairs: one side should strongly suggest exactly one counterpart."
            message += "\n- Keep each pair faithful to the source, but allow the model to choose the most playable atomic pair instead of the most obvious summary pair."
            message += "\n- Avoid bucket cards such as category -> examples, benefits/features -> sentence, or type family -> list of members."
            message += "\n- Do not use headings like benefits, types, categories, properties, examples, characteristics, or advantages as prompts unless the source gives one single canonical counterpart."
            message += "\n- Prefer a concrete surface form over a study heading: exact term, exact symbol, exact syntax, exact API, exact theorem name, exact event, exact title, exact identifier."

            if sourceProfile == .narrative {
                message += "\n- This source reads like narrative prose. Prefer character -> role, place -> significance, institution -> influence, event -> consequence, object/title -> meaning, or relationship -> dynamic."
                message += "\n- At most one pure person-name prompt in this batch unless the source is effectively a cast list."
            } else if sourceProfile == .symbolic {
                message += "\n- This source is notation-heavy or formal. Prefer notation -> meaning, rule/theorem -> canonical statement, structure -> defining property, symbol -> interpretation, expression -> named result."
                message += "\n- Keep formulas only when they are themselves the canonical counterpart."
                message += "\n- Preserve useful notation and operators instead of paraphrasing them away when they are the clearest cue."
            } else if sourceProfile == .code {
                message += "\n- This source looks code-like or technical. Prefer keyword/API/command -> purpose, syntax form -> meaning, parameter/flag -> effect, error/constraint -> cause, type/object -> role."
                message += "\n- Do not emit long prose definitions when a tighter technical counterpart exists."
                message += "\n- When the source shows exact syntax, exception names, signatures, operators, or method calls, prefer those exact technical forms as cues or counterparts."
                message += "\n- Use precise code fragments or identifiers when they teach better than plain prose. Short syntax snippets are allowed."
                message += "\n- In code-heavy batches, at least half of the pairs should preserve an exact technical surface form from the source when the source supports it."
                message += "\n- Prefer exact code cues such as `throws IOException`, `catch (...)`, `try (...)`, class names, method signatures, flags, operators, and exception names over generic labels like 'checked exceptions' or 'benefits of exceptions'."
                message += "\n- Avoid turning code material into taxonomy cards or example-list cards when an exact construct -> effect pair exists."
            }
        } else if cardType == .flashcards {
            message += "\n- Build atomic flashcards, not mini essays."
            message += "\n- Prefer one crisp recall task per card."
            message += "\n- Keep question_zones short and direct; avoid long multi-clause stems when a tighter cue works."
            message += "\n- Keep answer_zones high-signal and sized to the active card level. Simple should stay terse, balanced should develop one extra layer, and advanced may go deeper when the source supports it."
            message += "\n- Include a code block or formal expression only when it materially teaches the concept; avoid giant reference dumps."
            message += "\n- Do not spend multiple cards repeating the same high-level benefit/overview from slightly different angles."

            if sourceProfile == .symbolic {
                message += "\n- This source is notation-heavy or formal. Preserve exact notation, formulas, operators, and canonical statements when they are the clearest learning surface."
                message += "\n- Prefer theorem/rule -> statement, notation -> meaning, structure -> defining property, expression -> interpretation."
            } else if sourceProfile == .code {
                message += "\n- This source looks code-like or technical. Preserve exact identifiers, APIs, exception names, signatures, operators, and short syntax fragments when they teach better than prose."
                message += "\n- Prefer keyword/API/syntax/exception -> role, behavior, constraint, or effect."
                message += "\n- Use short code snippets only when they clarify the recall target. Avoid full example programs unless the snippet itself is the concept."
            } else if sourceProfile == .narrative {
                message += "\n- This source reads like narrative prose. Prefer character/figure -> role, event -> consequence, object/title -> meaning, relation -> dynamic, place -> significance."
                message += "\n- Avoid broad chapter-summary cards when a tighter concept, role, or event card exists."
            }
        }

        if !coveredPrompts.isEmpty {
            message += "\n- Avoid overlapping these already-covered prompts when possible:"
            for covered in coveredPrompts.prefix(4) {
                message += "\n  • \(covered)"
            }
        }

        if !approvedMatchExamples.isEmpty {
            message += "\n- Earlier strong Match pairs from this run. Use them only as a quality floor. Do NOT copy them mechanically:"
            for example in approvedMatchExamples.prefix(2) {
                message += "\n  • \(example)"
            }
        }

        if !matchOverlapHints.isEmpty {
            message += "\n- Avoid repeating or overlapping these earlier Match pairs:"
            for hint in matchOverlapHints.prefix(4) {
                message += "\n  • \(hint)"
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
        coveredPrompts: [String],
        approvedMatchExamples: [String],
        matchOverlapHints: [String]
    ) -> String {
        let generationInstruction = cardType == .match
            ? "Analyze only the attached source pages/images and generate UP TO \(targetCards) strong Match cards."
            : "Analyze only the attached source pages/images and generate EXACTLY \(targetCards) cards."

        var message = """
        \(generationInstruction)
        Batch \(batchIndex) of \(totalBatches).
        Source coverage: \(sourceLabel).
        Focus on distinct concepts from these specific pages/images.
        """

        if let languageHint = options.sourceLanguageHint {
            message += "\nThe natural-language output for this run is locked to \(languageHint.displayName) (\(languageHint.languageCode)). Keep every card fully in that language."
        }

        if passIndex > 1 {
            message += "\nThis source group has already been used in an earlier pass. Cover new concepts or a clearly different angle."
        }

        if cardType == .match {
            message += "\nDo not default to only label/name -> description cards."
            message += "\nFavor game-worthy atomic pairs that are easy to recognize quickly and do not require reading a mini explanation."
            message += "\nIf code or formal notation is visible, preserve exact technical forms when they are the clearest counterpart."
        } else if cardType == .flashcards {
            message += "\nBuild atomic flashcards, not mini essays."
            message += "\nPrefer short direct prompts and concise high-signal answers."
            message += "\nIf code or formal notation is visible, preserve exact technical forms when they teach better than paraphrase."
            message += "\nUse code blocks only when they materially clarify the concept."
        }

        if !coveredPrompts.isEmpty {
            message += "\nAvoid overlapping these already-covered prompts when possible:"
            for covered in coveredPrompts.prefix(4) {
                message += "\n- \(covered)"
            }
        }

        if !approvedMatchExamples.isEmpty {
            message += "\nEarlier strong Match pairs from this run. Use them only as a quality floor. Do NOT copy them mechanically:"
            for example in approvedMatchExamples.prefix(2) {
                message += "\n- \(example)"
            }
        }

        if !matchOverlapHints.isEmpty {
            message += "\nAvoid repeating or overlapping these earlier Match pairs:"
            for hint in matchOverlapHints.prefix(4) {
                message += "\n- \(hint)"
            }
        }

        return message
    }

    nonisolated func conversionUserMessage(
        sourceCards: [AICardConversionSource],
        targetType: AICardGenerationType,
        targetCount: Int? = nil,
        approvedMatchExamples: [String] = [],
        matchOverlapHints: [String] = []
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
            let resolvedTargetCount = max(1, targetCount ?? sourceCards.count)
            var message = """
            Convert the source cards below into UP TO \(resolvedTargetCount) \(targetType.title) outputs.
            Preserve the dominant language of each source card.
            Return ONLY the strongest usable Match pairs from this candidate set.
            You MAY skip a source card if it cannot produce a crisp, unambiguous Match pair.
            Return AT MOST one result per SOURCE_INDEX.

            CRITICAL FOR MATCH:
            - Do NOT mechanically paraphrase the whole front/back pair.
            - Extract the single best atomic cue -> counterpart pair from each source card.
            - Keep the pairing style coherent, but do not force one fixed pattern when the source suggests a better pair.
            - Prefer canonical study pairs such as concept -> definition, notation -> meaning, rule name -> rule statement, symbol -> interpretation.
            - For narrative or literature cards, prefer character -> role, place -> significance, relation -> dynamic, title/object -> meaning, event -> consequence.
            - For formal or math-heavy cards, prefer notation -> meaning, theorem/rule -> canonical statement, expression -> named result, structure -> defining property.
            - For code or technical cards, prefer API/keyword/command -> purpose, syntax -> meaning, flag/parameter -> effect, type/object -> role.
            - If the source card is broad, choose the most concrete sub-concept that still teaches something useful.
            - The answer must be the direct counterpart, not an explanation, proof sketch, or mini flashcard back.
            - Prefer answers that are unique inside the batch and would not plausibly match several prompts.
            - Avoid letting the whole batch collapse into only name -> descriptor cards.
            - Avoid bucket cards such as category -> examples, benefits/features -> sentence, family name -> list of members, or topic heading -> broad description.
            - Prefer a concrete source surface instead of a chapter-style heading: exact symbol, exact theorem name, exact syntax, exact API, exact exception name, exact event, exact title.
            - The result should feel good in a fast learning game: compact, specific, memorable, and easy to pair correctly.
            - If the source visibly contains code, syntax, signatures, API names, exceptions, operators, or formal notation, preserve those exact forms whenever they are the most faithful cue or counterpart.
            - Do not flatten code-heavy or notation-heavy cards into generic prose if a short technical form would teach better.
            - For code-heavy cards, prefer exact snippets or identifiers such as `throws IOException`, `try (...)`, `finally`, `NullPointerException`, `AutoCloseable`, method names, signatures, flags, or operators.
            - Do not default to cards like `checked exceptions -> ...`, `benefits of exceptions -> ...`, or `examples of X -> ...` when the source contains exact code or syntax that can form a tighter pair.
            """

            if !approvedMatchExamples.isEmpty {
                message += "\n\nEARLIER STRONG MATCH PAIRS (quality floor only; do not copy them mechanically):"
                for example in approvedMatchExamples.prefix(2) {
                    message += "\n- \(example)"
                }
            }

            if !matchOverlapHints.isEmpty {
                message += "\n\nAVOID OVERLAP WITH THESE EARLIER PAIRS:"
                for hint in matchOverlapHints.prefix(8) {
                    message += "\n- \(hint)"
                }
            }

            message += "\n\nSOURCE CARDS:\n\n\(body)"
            return message
        }

        return """
        Convert each source card below into ONE \(targetType.title) output.
        Preserve the dominant language of each source card.
        Keep the order stable and return one result for every SOURCE_INDEX.

        SOURCE CARDS:

        \(body)
        """
    }

    nonisolated func formattedMatchApprovedExamples(
        from cards: [AIFlashcard],
        limit: Int = 4
    ) -> [String] {
        cards.compactMap { card in
            guard case .match(let content) = card.content else { return nil }
            let prompt = content.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = content.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty, !answer.isEmpty else { return nil }
            return "\"\(prompt)\" -> \"\(answer)\""
        }
        .prefix(limit)
        .map { $0 }
    }

    nonisolated func formattedMatchApprovedExamples(
        from outputs: [AICardConversionOutput],
        limit: Int = 4
    ) -> [String] {
        formattedMatchApprovedExamples(
            from: outputs.map(\.generatedCard),
            limit: limit
        )
    }

    nonisolated func formattedMatchOverlapHints(
        from cards: [AIFlashcard],
        limit: Int = 8
    ) -> [String] {
        cards.compactMap { card in
            guard case .match(let content) = card.content else { return nil }
            let prompt = content.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = content.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty, !answer.isEmpty else { return nil }
            return "\(prompt) -> \(answer)"
        }
        .prefix(limit)
        .map { $0 }
    }

    nonisolated func formattedMatchOverlapHints(
        from outputs: [AICardConversionOutput],
        limit: Int = 8
    ) -> [String] {
        formattedMatchOverlapHints(
            from: outputs.map(\.generatedCard),
            limit: limit
        )
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
        if options.cardType == .match {
            return matchSystemPrompt(targetCards: targetCards, isOCR: isOCR, options: options)
        }
        if options.cardType == .flashcards {
            return flashcardSystemPrompt(
                targetCards: targetCards,
                isOCR: isOCR,
                level: options.cardLevel,
                options: options
            )
        }

        let outputContract = options.cardType.outputContract
        var prompt = #"""
        You are a rigorous University Professor AI specialized in generating elite, in-depth "Active Recall" flashcards.
        Your absolute priority is TECHNICAL DEPTH, ACCURACY, and HIGH READABILITY.
        
        Output STRICTLY valid JSON with EXACTLY \#(targetCards) cards.
        
        \#(languageRulePrompt(for: options))
        
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

    nonisolated func flashcardSystemPrompt(
        targetCards: Int,
        isOCR: Bool,
        level: AICardGenerationLevel,
        options: AIGenerationOptions
    ) -> String {
        var prompt = #"""
        You generate high-signal active-recall flashcards.
        Your job is to produce accurate, compact, teachable cards that preserve the real surface of the source when that helps learning.

        Output STRICTLY valid JSON with EXACTLY \#(targetCards) cards.

        \#(languageRulePrompt(for: options))

        LATEX IN JSON
        Every LaTeX command that starts with one backslash must be written with EXACTLY two backslashes in JSON.
        Example: \lambda in the final card must appear as \\lambda in JSON.
        Never write four backslashes before a LaTeX command.
        """#

        prompt += requiredJSONSchemaPrompt(for: .flashcard)
        prompt += formattingRulesPrompt(for: .flashcard)

        if isOCR {
            prompt += """

        OCR CORRECTION MODE ENABLED
        Repair broken words, split hyphenations, noisy symbols, damaged code syntax, and corrupted notation before generating cards.
        """
        }

        prompt += cardTypePromptAddition(for: .flashcards)
        prompt += cardLevelPromptAddition(for: level)
        return prompt
    }

    nonisolated func matchSystemPrompt(
        targetCards: Int,
        isOCR: Bool,
        options: AIGenerationOptions
    ) -> String {
        var prompt = """
        You generate Match cards for a fast two-column matching game.
        Your job is to extract compact, canonical cue -> counterpart pairs that are easy to pair quickly, feel good in a learning game, and still teach something real.
        Output STRICTLY valid JSON with UP TO \(targetCards) cards.

        \(languageRulePrompt(for: options))

        LATEX IN JSON
        If you use LaTeX, every command that starts with one backslash must be written with EXACTLY two backslashes in JSON.
        Example: \\lambda in the final card must appear as \\\\lambda in JSON.
        Never write four backslashes before a LaTeX command.
        """

        prompt += requiredJSONSchemaPrompt(for: .match)
        prompt += formattingRulesPrompt(for: .match)

        if isOCR {
            prompt += """

        OCR CORRECTION MODE ENABLED
        Repair broken words, joined headings, split hyphenations, misrecognized quotes, and damaged symbols before extracting pairs.
        If a source line is noisy, recover the intended concept first, then generate the pair.
        """
        }

        prompt += """

        MATCH PAIR QUALITY RULES
        - Build crisp study pairs, not mini flashcards.
        - Think in terms of playable counterparts, not just compressed summaries.
        - The best pair is the one where the learner can see one side and strongly infer one exact counterpart.
        - prompt should usually be a short term, label, title, role, notation, object, event, structure name, command, theorem name, API, exact identifier, syntax fragment, or compact cue.
        - answer must be the direct counterpart only, not a summary, list, or explanation.
        - one short sentence is allowed only if that is the smallest faithful counterpart.
        - keep the batch coherent, but let the source decide what the strongest counterpart is.
        - avoid question-style prompts.
        - avoid broad prompts like "characteristics of", "functions of", or "elements of" unless the source itself defines one atomic counterpart.
        - avoid category/list cards such as “examples of X”, “benefits of X”, “types of X”, “properties of X”, or “advantages of X”.
        - if a source idea is too broad, extract one tighter sub-concept.
        - if a source fragment still cannot yield a crisp pair, skip it rather than padding the batch with weak cards.
        - do not invent facts, hidden relations, or implied meanings that are not grounded in the source.
        - if the source contains code, stack traces, signatures, operators, or formal notation, preserve those exact technical forms whenever they are the best learning surface.
        - if a short code snippet or notation fragment is the clearest counterpart, you may output it verbatim as a plain string.
        - preserve useful variety across domains:
          • math/formal: notation -> meaning, theorem/rule -> canonical statement, structure -> property
          • code/technical: keyword/API/command -> purpose, syntax -> meaning, flag/parameter -> effect
          • narrative/history/theology: person -> role, place -> significance, event -> consequence, title/object -> meaning
          • science/general study: concept -> definition, process -> outcome, structure -> function, cause -> effect
        """

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
        case .flashcard:
            return """

        ═══════════════════════════════════════════════════════
        ZONE SPLITTING & READABILITY
        ═══════════════════════════════════════════════════════
        Break answers into small, readable zones.
        Prefer concise high-signal recall answers over long textbook explanations.

        RULE: The active card level controls the density budget.
        RULE: Simple should usually use 1 short question zone and 1-2 short answer zones.
        RULE: Balanced should usually use 1-2 question zones and 2-4 answer zones.
        RULE: Advanced may use 1-2 question zones and 3-6 answer zones when the added depth materially improves the card.
        RULE: Use a code block or display equation only when it materially teaches the concept.
        RULE: Avoid list dumps, long bullet cascades, and repeated paraphrases of the same idea.

        ═══════════════════════════════════════════════════════
        FORMATTING RULES (STRICT)
        ═══════════════════════════════════════════════════════
        - TEXT HIGHLIGHTS: Highlight the crucial concept using double asterisks when it improves recall.
        - INLINE CODE: Use single backticks (`) for short syntax, class names, APIs, or technical terms.
        - INLINE MATH: Wrap every math symbol, variable, and inline equation in single $.
        - BLOCK MATH: Wrap display equations in double $$ only when the equation itself is important.
        - BLOCK CODE: Triple-backtick code blocks MUST be in their own standalone string in the array.
        - Prefer one atomic recall target per card.
        - Do not spend multiple zones restating the same definition in slightly different words.
        """
        case .quiz:
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

        FORMATTING RULES (STRICT)
        - prompt and answer MUST stay plain, compact, and immediately scannable.
        - Prefer a single line for each field. Avoid bullet points, numbering, and sentence fragments stacked across lines.
        - Think in compact pairs only.
        - The pair should feel like a direct textbook or story-world counterpart, not like two vaguely related study notes.
        - The answer must uniquely resolve the prompt among neighboring cards in the same batch.
        - Each field should feel readable in about one second.
        - Avoid markdown emphasis unless a math or code symbol is essential to the concept.
        - Never include examples, proof sketches, scene summaries, or qualifiers beyond the direct pair itself.
        - Never output lists, semicolon chains, or mini paragraphs.
        - Avoid generic answers that could match many prompts in the same deck.
        - If the source concept is too broad for a compact pair, skip it and generate a tighter concept instead.
        - Avoid category/list pairs such as "examples of X", "benefits of X", "types of X", "properties of X", or "advantages of X".
        - Prefer exact syntax, identifiers, symbols, theorem names, event names, titles, APIs, flags, exception names, or notation over broad topical headings.
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
        level: AICardGenerationLevel,
        requestedResultCount: Int? = nil
    ) -> String {
        if targetType == .match {
            return matchConversionSystemPrompt(
                sourceCount: sourceCount,
                requestedResultCount: requestedResultCount
            )
        }

        let resolvedTargetCount = max(1, requestedResultCount ?? sourceCount)
        let resultLine: String
        let omissionLine: String

        if targetType == .match {
            resultLine = "Output STRICTLY valid JSON with UP TO \(resolvedTargetCount) results."
            omissionLine = "- You MAY omit a source_index only when that source cannot yield a crisp, unambiguous Match pair."
        } else {
            resultLine = "Output STRICTLY valid JSON with EXACTLY \(sourceCount) results."
            omissionLine = "- Do not omit any source_index."
        }

        var prompt = """
        You are a rigorous study-card conversion engine.
        Convert existing cards into a new target format without inventing unsupported facts.

        \(resultLine)

        ═══════════════════════════════════════════════════════
        CONVERSION RULES (CRITICAL)
        ═══════════════════════════════════════════════════════
        - Preserve the dominant language of each source card.
        - Each result MUST map to one source card via its exact source_index.
        - Keep the semantic core intact, but adapt the phrasing to the target card format.
        - Do not merge multiple source cards into one output.
        \(omissionLine)
        - When a source is verbose, compress it into the smallest faithful target representation.
        - Do not add meta commentary such as "converted card", "answer", "prompt", or numbering inside the generated fields.

        ═══════════════════════════════════════════════════════
        LATEX ESCAPING IN JSON
        ═══════════════════════════════════════════════════════
        Every LaTeX command that starts with one backslash must be written with EXACTLY two backslashes in the JSON string.
        Example: \\lambda in the final card must appear as \\\\lambda in the JSON output.
        Never write four backslashes before a LaTeX command.
        """

        prompt += requiredConversionSchemaPrompt(
            for: targetType.outputContract,
            requestedResultCount: requestedResultCount,
            sourceCount: sourceCount
        )
        prompt += formattingRulesPrompt(for: targetType.outputContract)
        prompt += cardTypePromptAddition(for: targetType)
        prompt += cardLevelPromptAddition(for: level)

        return prompt
    }

    nonisolated func matchConversionSystemPrompt(
        sourceCount: Int,
        requestedResultCount: Int? = nil
    ) -> String {
        let resolvedTargetCount = max(1, requestedResultCount ?? sourceCount)

        return """
        You are a precise Match-card conversion engine.
        Convert existing cards into compact, canonical Match pairs without inventing unsupported facts.

        Output STRICTLY valid JSON with UP TO \(resolvedTargetCount) results.

        ═══════════════════════════════════════════════════════
        CONVERSION RULES (CRITICAL)
        ═══════════════════════════════════════════════════════
        - Preserve the dominant language of each source card.
        - Each result MUST map to one provided source_index.
        - You MAY skip a source card if it cannot produce a crisp Match pair.
        - Return AT MOST one result per SOURCE_INDEX.
        - Do not merge several source cards into one pair.
        - Extract one atomic cue -> counterpart pair from the source, not a broad summary.
        - Keep the pairing style consistent across the batch whenever possible, but preserve useful variety across the run.
        - Prefer canonical study pairs: concept -> definition, notation -> meaning, motif -> role, rule name -> statement, structure -> property, command/API -> purpose, syntax fragment -> meaning.
        - Avoid question-style prompts, long explanations, or list-like answers.
        - Avoid category/list prompts such as benefits, examples, types, categories, properties, or advantages unless the source itself gives one exact canonical counterpart.
        - If a source card is broad, pick the tightest faithful sub-concept instead of paraphrasing everything.
        - The result should feel good in a fast learning game: specific, memorable, and easy to pair correctly.
        - If the source contains code, operators, signatures, exception names, or formal notation, preserve those exact technical forms whenever they are the clearest learning surface.
        - Prefer exact code/symbol surfaces over generic prose when the source itself teaches through code or notation.

        ═══════════════════════════════════════════════════════
        LATEX IN JSON
        ═══════════════════════════════════════════════════════
        If you use LaTeX, every command that starts with one backslash must be written with EXACTLY two backslashes in JSON.
        """
        + requiredConversionSchemaPrompt(for: .match, requestedResultCount: requestedResultCount, sourceCount: sourceCount)
        + formattingRulesPrompt(for: .match)
    }

    nonisolated func requiredConversionSchemaPrompt(
        for contract: AIGeneratedCardContract,
        requestedResultCount: Int? = nil,
        sourceCount: Int
    ) -> String {
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
            let resolvedTargetCount = max(1, requestedResultCount ?? sourceCount)
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
        - "results" MUST contain UP TO \(resolvedTargetCount) objects, never more.
        - "source_index" MUST exactly match a source card index provided in the prompt.
        - Each "source_index" may appear at most once.
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
        Generate classic active-recall cards with a strong question on the front and a concise high-signal answer on the back.
        Prefer one core concept, mechanism, theorem, API, exception, event, symbol, or tightly scoped relation per card.
        The best flashcards feel direct and memorable, not like mini lecture notes.
        Keep the front focused on one recall target.
        Keep the back compact and layered only as much as needed to teach the concept well.
        For code-heavy sources, preserve exact identifiers, syntax, operators, exception names, signatures, and short snippets when they teach better than prose.
        For symbolic or math-heavy sources, preserve notation, formulas, operators, and canonical statements when they are the clearest learning surface.
        Avoid broad “list all benefits/properties/types” cards unless the source itself is explicitly teaching a compact enumeration worth memorizing.
        Avoid turning one source concept into a long narrative explanation with many redundant zones.
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
        The pair should feel playable: seeing one side should strongly suggest one exact counterpart.
        Keep the relation family consistent across the batch whenever possible.
        Do not force one artificial relation-family template across all batches.
        If the source is phrased as a long question, extract the underlying concept name or notation instead of copying the whole question style.
        If the source answer contains several clauses, keep only the single canonical counterpart that best teaches the concept.
        Use formulas as answers only when the source concept is itself a named rule/schema and the formula is the canonical statement of that rule.
        If the source contains code, preserve exact identifiers, operators, signatures, exception names, and short syntax fragments when they teach better than prose.
        Prefer exact code/token surfaces like `throws IOException`, `finally`, `catch (...)`, `AutoCloseable`, operators, annotations, and method signatures over bucket headings like "checked exceptions" or "benefits of exceptions".
        Avoid cards of the form category -> examples, benefits -> sentence, or topic heading -> broad description.
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

    nonisolated func preparedSourceTextForPrompt(
        _ text: String,
        cardType: AICardGenerationType,
        needsOCRCorrection: Bool,
        targetCards: Int
    ) -> String {
        switch cardType {
        case .match:
            let separator = DocumentTextExtractor.pageSeparator
            let normalizedBlocks = text
                .components(separatedBy: separator)
                .map { normalizeMatchPromptBlock($0, needsOCRCorrection: needsOCRCorrection) }
                .filter { !$0.isEmpty }

            guard !normalizedBlocks.isEmpty else { return "" }

            let totalBudget = max(2_400, min(4_600, 1_400 + (targetCards * 850)))
            let joined = normalizedBlocks.joined(separator: "\n\n\(separator)\n\n")

            guard joined.count > totalBudget else {
                return joined
            }

            let blockBudget = max(260, totalBudget / max(normalizedBlocks.count, 1))
            let compactedBlocks = normalizedBlocks.map { compactMatchPromptBlock($0, budget: blockBudget) }
            let compactedJoined = compactedBlocks.joined(separator: "\n\n\(separator)\n\n")

            guard compactedJoined.count > totalBudget else {
                return compactedJoined
            }

            return compactMatchPromptBlock(compactedJoined, budget: totalBudget)
        case .flashcards:
            let separator = DocumentTextExtractor.pageSeparator
            let normalizedBlocks = text
                .components(separatedBy: separator)
                .map { normalizeFlashcardPromptBlock($0, needsOCRCorrection: needsOCRCorrection) }
                .filter { !$0.isEmpty }

            guard !normalizedBlocks.isEmpty else { return "" }

            let totalBudget = max(2_800, min(5_400, 1_700 + (targetCards * 450)))
            let joined = normalizedBlocks.joined(separator: "\n\n\(separator)\n\n")

            guard joined.count > totalBudget else {
                return joined
            }

            let blockBudget = max(360, totalBudget / max(normalizedBlocks.count, 1))
            let compactedBlocks = normalizedBlocks.map { compactFlashcardPromptBlock($0, budget: blockBudget) }
            let compactedJoined = compactedBlocks.joined(separator: "\n\n\(separator)\n\n")

            guard compactedJoined.count > totalBudget else {
                return compactedJoined
            }

            return compactFlashcardPromptBlock(compactedJoined, budget: totalBudget)
        default:
            return text
        }
    }

    nonisolated func formattedStrongMatchApprovedExamples(
        from cards: [AIFlashcard],
        limit: Int = 2
    ) -> [String] {
        cards.compactMap { card in
            guard case .match(let content) = card.content else { return nil }
            let evaluation = MatchCardQualityPolicy.evaluate(
                prompt: content.prompt,
                answer: content.answer
            )
            guard evaluation.isStrongExample else { return nil }
            return "\"\(evaluation.prompt)\" -> \"\(evaluation.answer)\""
        }
        .prefix(limit)
        .map { $0 }
    }

    nonisolated func formattedStrongMatchApprovedExamples(
        from outputs: [AICardConversionOutput],
        limit: Int = 2
    ) -> [String] {
        formattedStrongMatchApprovedExamples(
            from: outputs.map(\.generatedCard),
            limit: limit
        )
    }

    nonisolated func resolvedGenerationOptions(
        for text: String,
        needsOCRCorrection: Bool,
        base options: AIGenerationOptions
    ) -> AIGenerationOptions {
        if options.outputLanguageMode == .manual,
           let manualLanguage = options.manualOutputLanguage {
            var resolved = options
            resolved.sourceLanguageHint = manualLanguage
            return resolved
        }

        guard options.sourceLanguageHint == nil,
              let languageHint = detectSourceLanguageHint(
                from: text,
                needsOCRCorrection: needsOCRCorrection
              ) else {
            return options
        }

        var resolved = options
        resolved.sourceLanguageHint = languageHint
        return resolved
    }

    nonisolated func resolvedVisionGenerationOptions(
        base options: AIGenerationOptions
    ) -> AIGenerationOptions {
        guard options.outputLanguageMode == .manual,
              let manualLanguage = options.manualOutputLanguage else {
            return options
        }

        var resolved = options
        resolved.sourceLanguageHint = manualLanguage
        return resolved
    }

    nonisolated func detectSourceLanguageHint(
        from text: String,
        needsOCRCorrection: Bool
    ) -> AIGenerationLanguageHint? {
        let sample = languageDetectionSample(
            from: text,
            needsOCRCorrection: needsOCRCorrection
        )

        guard sample.count >= 80 else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)

        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        guard let best = hypotheses.max(by: { $0.value < $1.value }),
              best.value >= 0.35 else {
            return nil
        }

        let languageCode = best.key.rawValue
        let displayName = Locale(identifier: "en_US_POSIX")
            .localizedString(forLanguageCode: languageCode)?
            .capitalized ?? languageCode.uppercased()

        return AIGenerationLanguageHint(
            languageCode: languageCode,
            displayName: displayName
        )
    }

    nonisolated func languageDetectionSample(
        from text: String,
        needsOCRCorrection: Bool
    ) -> String {
        let normalized = normalizeFlashcardPromptBlock(
            text.replacingOccurrences(of: DocumentTextExtractor.pageSeparator, with: "\n"),
            needsOCRCorrection: needsOCRCorrection
        )

        let candidateLines = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let naturalLanguageLines = candidateLines.filter { line in
            let scalars = line.unicodeScalars.filter { !$0.properties.isWhitespace }
            guard !scalars.isEmpty else { return false }
            let letterCount = scalars.filter { CharacterSet.letters.contains($0) }.count
            return letterCount >= 8 && Double(letterCount) / Double(scalars.count) >= 0.55
        }

        let joined = naturalLanguageLines
            .prefix(120)
            .joined(separator: " ")

        if joined.count >= 160 {
            return String(joined.prefix(4_500))
        }

        return String(normalized.prefix(4_500))
    }

    nonisolated func languageRulePrompt(for options: AIGenerationOptions) -> String {
        if let languageHint = options.sourceLanguageHint {
            return """
            LANGUAGE RULE (CRITICAL)
            The output language for this run is locked to \(languageHint.displayName) (\(languageHint.languageCode)).
            Every generated card in this run MUST be fully written in \(languageHint.displayName).
            Do not translate concepts into another natural language.
            Do not switch languages between batches.
            Keep code, formulas, identifiers, API names, symbols, and proper nouns exactly as they appear in the source.
            """
        }

        return """
        LANGUAGE RULE (CRITICAL)
        Match the dominant language of the source exactly.
        Do not translate concepts to English.
        Do not mix languages unless the source itself mixes them.
        """
    }

    nonisolated func matchSourceProfile(for text: String) -> MatchSourceProfile {
        let lowercased = text.lowercased()
        let symbolicSignals = [
            "\\", "⊢", "∀", "∃", "∑", "∫", "∈", "→", "⇒", "⇔", "λ", "φ", "τ",
            "matrix", "theorem", "lemma", "proposition", "degree", "graph", "logic", "formula"
        ]
        let codeSignals = [
            "func ", "class ", "struct ", "enum ", "return", "let ", "var ", "public ", "private ",
            "const ", "function", "def ", "import ", "console.", "select ", "where ", "{", "}", "=>"
        ]
        let narrativeSignals = [
            "chapter", "prince", "emperor", "bishop", "cardinal", "pope",
            "palace", "chamber", "eyes", "gaze", "kiss", "breath", "dialogue"
        ]
        let academicSignals = [
            "definition", "theorem", "formula", "property", "structure", "represents",
            "is called", "is defined", "proof", "criterion", "notation"
        ]

        let symbolicScore = symbolicSignals.reduce(into: 0) { score, signal in
            if lowercased.contains(signal) || text.contains(signal) { score += 1 }
        }

        let codeScore = codeSignals.reduce(into: 0) { score, signal in
            if lowercased.contains(signal) || text.contains(signal) { score += 1 }
        }

        let narrativeScore = narrativeSignals.reduce(into: 0) { score, signal in
            if lowercased.contains(signal) { score += 1 }
        } + (text.contains("—") ? 2 : 0)

        let academicScore = academicSignals.reduce(into: 0) { score, signal in
            if lowercased.contains(signal) { score += 1 }
        }

        if codeScore >= max(symbolicScore, academicScore, narrativeScore) + 2 {
            return .code
        }

        if symbolicScore >= max(codeScore, academicScore, narrativeScore) + 1 {
            return .symbolic
        }

        if narrativeScore >= academicScore + 2 {
            return .narrative
        }

        if academicScore >= narrativeScore + 2 {
            return .academic
        }

        return .generic
    }

    nonisolated func normalizeMatchPromptBlock(
        _ text: String,
        needsOCRCorrection: Bool
    ) -> String {
        var normalized = text
        if needsOCRCorrection {
            normalized = normalized.replacingOccurrences(
                of: #"(?<=[\p{L}])-\s*\n\s*(?=[\p{L}])"#,
                with: "",
                options: .regularExpression
            )
        }

        normalized = normalized
            .replacingOccurrences(
                of: #"\n\s*\d{1,3}\s*\n"#,
                with: "\n",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "„", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "—", with: "-")

        return normalized
    }

    nonisolated func normalizeFlashcardPromptBlock(
        _ text: String,
        needsOCRCorrection: Bool
    ) -> String {
        var normalized = text
        if needsOCRCorrection {
            normalized = normalized.replacingOccurrences(
                of: #"(?<=[\p{L}])-\s*\n\s*(?=[\p{L}])"#,
                with: "",
                options: .regularExpression
            )
        }

        normalized = normalized
            .replacingOccurrences(
                of: #"\n\s*\d{1,3}\s*\n"#,
                with: "\n",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "„", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "—", with: "-")

        return normalized
    }

    nonisolated func compactMatchPromptBlock(
        _ text: String,
        budget: Int
    ) -> String {
        guard text.count > budget else { return text }
        guard budget > 160 else { return String(text.prefix(budget)) }

        let headBudget = Int(Double(budget) * 0.58)
        let tailBudget = max(0, budget - headBudget - 5)
        let head = compactMatchPromptEdge(String(text.prefix(headBudget)), trimFromStart: false)
        let tail = compactMatchPromptEdge(String(text.suffix(tailBudget)), trimFromStart: true)
        return "\(head) ... \(tail)"
    }

    nonisolated func compactMatchPromptEdge(
        _ text: String,
        trimFromStart: Bool
    ) -> String {
        guard !text.isEmpty else { return text }
        if trimFromStart, let firstWhitespace = text.firstIndex(where: \.isWhitespace) {
            return String(text[text.index(after: firstWhitespace)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !trimFromStart, let lastWhitespace = text.lastIndex(where: \.isWhitespace) {
            return String(text[..<lastWhitespace]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated func compactFlashcardPromptBlock(
        _ text: String,
        budget: Int
    ) -> String {
        guard text.count > budget else { return text }
        guard budget > 200 else { return String(text.prefix(budget)) }

        let headBudget = Int(Double(budget) * 0.68)
        let tailBudget = max(0, budget - headBudget - 7)
        let head = compactFlashcardPromptEdge(String(text.prefix(headBudget)), trimFromStart: false)
        let tail = compactFlashcardPromptEdge(String(text.suffix(tailBudget)), trimFromStart: true)
        return "\(head)\n\n...\n\n\(tail)"
    }

    nonisolated func compactFlashcardPromptEdge(
        _ text: String,
        trimFromStart: Bool
    ) -> String {
        guard !text.isEmpty else { return text }

        let separators = CharacterSet(charactersIn: "\n.?!:;")
        let scalars = Array(text.unicodeScalars)

        if trimFromStart {
            if let boundary = scalars.firstIndex(where: { separators.contains($0) }) {
                let nextIndex = scalars.index(after: boundary)
                if nextIndex < scalars.endIndex {
                    return String(String.UnicodeScalarView(scalars[nextIndex...])).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } else if let boundary = scalars.lastIndex(where: { separators.contains($0) }) {
            return String(String.UnicodeScalarView(scalars[...boundary])).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated func cardLevelPromptAddition(for level: AICardGenerationLevel) -> String {
        switch level {
        case .simple:
            return """

        ═══════════════════════════════════════════════════════
        CARD LEVEL PROFILE — SIMPLE
        ═══════════════════════════════════════════════════════
        Keep the card short, direct, and immediately useful.
        The learner should get the core idea fast without reading a long answer.
        Focus on the clearest fact, definition, mapping, rule, or cause-effect relation.
        Prefer the minimum wording that still teaches the concept correctly.
        Do not pad the answer with extra nuance unless it is necessary for correctness.
        For flashcards, simple usually means:
        - 1 short question zone
        - 1-2 short answer zones
        - one core fact, mapping, rule, or definition
        - no secondary examples, caveats, or extended mechanism unless needed for correctness
        Treat the depth budget as intentionally tight.
        """
        case .balanced:
            return """

        ═══════════════════════════════════════════════════════
        CARD LEVEL PROFILE — BALANCED
        ═══════════════════════════════════════════════════════
        Keep the card clear and technically correct, but develop the idea more than in simple mode.
        Add one useful layer of explanation, context, mechanism, or contrast when it materially improves learning.
        The answer should still feel compact and readable, but it may contain more detail than simple mode.
        For flashcards, balanced should usually mean:
        - 1-2 question zones
        - 2-4 answer zones
        - the core answer plus one helpful layer such as mechanism, contrast, constraint, or short example
        - enough detail to explain the idea, not just name it
        """
        case .advanced:
            return """

        ═══════════════════════════════════════════════════════
        CARD LEVEL PROFILE — ADVANCED
        ═══════════════════════════════════════════════════════
        Extract the maximum useful depth supported by the source.
        Be explicit, precise, and thorough about mechanisms, distinctions, caveats, structure, or implications when they matter.
        Do not write an essay, but do not artificially compress the answer just to save space.
        If the source supports richer explanation, use it.
        Questions should test real understanding, not just surface memorization.
        For flashcards, advanced should usually mean:
        - 1-2 precise question zones
        - 3-6 answer zones when justified
        - explicit mechanism, distinction, caveat, structure, or example when it materially improves the card
        - enough detail to fully unpack the concept without drifting into essay padding
        """
        }
    }

    // -------------------------------------------------------------------------
}
