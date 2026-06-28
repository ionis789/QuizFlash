//
//  AIPromptBundleFixture.swift
//  QuizFlashTests
//

import XCTest
@testable import QuizFlash

enum AIPromptBundleFixture {
    static func bundle(version: String = "v3") throws -> AIPromptBundle {
        let templates = templates
        return AIPromptBundle(
            version: version,
            hash: try AIPromptBundle.hashTemplates(templates),
            status: "active",
            templates: templates
        )
    }

    static let templates: [String: String] = [
        "cardType.flashcard": """

CARD TYPE: FLASHCARDS
Create active-recall question/answer cards. Preserve exact technical terms, notation, formulas, and short code snippets when they are the best learning surface.
""",
        "cardType.quiz": """

CARD TYPE: QUIZ
Create multiple-choice questions that use the question stem to test understanding. When the answer is a compact term, construct, API, or convention, keep the choices compact instead of turning every choice into a paragraph. Keep choices parallel in shape and length when possible.
""",
        "depth.pro": """

DEPTH: PRO
Make cards deeper and more complete without becoming essays.
Include useful structure when the source supports it: statement plus condition, formula plus interpretation, rule plus exception, concept plus contrast, snippet plus behavior, or cause plus consequence.
For formal content, preserve the important symbolic statement and add only the minimal explanation needed.
For code content, preserve exact syntax and add the relevant behavior, constraint, output, or failure mode.
For narrative content, use precise terminology, selective **bold** emphasis, and segmented explanation that keeps distinct ideas visually separate.
For flashcards, use focused back zones when the source supports real depth, but avoid padding the answer with filler zones.
For quiz cards, use stronger distractors and a concise explanation that teaches the key distinction.
Use more zones only when each zone carries a distinct semantic role and improves readability.
""",
        "depth.simple": """

DEPTH: SIMPLE
Make cards short, clear, and immediately useful.
Preserve the essential recall target: definition, rule, formal statement, condition, relation, syntax, date, cause/effect, or distinction.
Do not remove notation or exact syntax when that is the core idea.
Do not dumb down the content: keep the card correct and testable, but remove secondary nuance, long examples, and proof details.
Use fewer zones when the idea is truly simple, but still split prose when separation makes the answer clearer or less crowded.
For flashcards, keep the front concise and let the back use only as many zones as the core answer needs.
For quiz cards, test one direct idea with compact choices.
""",
        "language.auto": """
LANGUAGE RULE
Use the dominant natural language of the source text.
Preserve quoted terms, formulas, code, and proper nouns exactly when needed.
""",
        "language.locked": """
LANGUAGE RULE
Write every generated card in {{languageDisplayName}} ({{languageCode}}).
Do not mix languages unless the source itself contains a quoted term, formula, code, or proper noun.
""",
        "sourceProfile.system": """
You analyze QuizFlash source material before card generation.
Return STRICT JSON only with this shape: {"deck_title":"...","language_code":"...","language_display_name":"..."}.
Infer the dominant natural language and a concise study deck title from the source itself.
Do not translate the title away from the source language.
If the source is too ambiguous, keep fields conservative rather than guessing wildly.
""",
        "sourceProfile.user": """
Analyze this source and return the JSON profile only:

{{text}}
""",
        "layout.flashcard": """

MOBILE LAYOUT
Keep each question readable on a phone card. Keep answer zones scannable and avoid dense paragraphs.
Prefer 1 short front zone. Use 2 front zones only for a short context line plus the actual prompt.
Simple answers should stay compact. Pro answers may use more segmentation when the concept needs structure.
Do not force the same number of zones across cards; choose the clearest natural structure that stays readable and avoids crowding.
For prose-heavy cards, split answers into semantic text zones whenever that makes the card easier to scan.
Use selective **bold** emphasis to make important terms visible during review.
If a source section is broad, create multiple cards instead of one overloaded card.
Code snippets should use standalone code zones when block structure itself teaches the concept. Keep compact syntax in text zones with inline backticks when it reads better inline.
""",
        "layout.quiz": """

MOBILE LAYOUT
Keep the question and choices compact enough for a phone screen. Avoid choices that differ only by tiny wording.
Use a short question stem, compact choices, and a brief focused explanation when it helps.
Math-heavy quiz questions should avoid a single dense setup paragraph; keep long formulas in their own question zone so they can occupy a clean full-width line.
Prefer short answer choices that can be scanned as terms, constructs, or phrases when the source supports that; avoid prose choices for questions whose answer can be a compact keyword or construct.
If the concept requires a long setup, generate a flashcard-style explanation only in the explanation zone, not inside choices.
Code snippets should use standalone code zones when block structure is needed to test exact behavior or syntax. Keep compact syntax choices in text zones with inline backticks when that is clearer.
""",
        "rules.flashcard": """

FLASHCARD RULES
- Prefer one atomic recall target per card.
- Keep prompts concise and direct.
- Every answer text zone must contain exactly one complete sentence or independent statement. Split separate claims into separate zones; do not return one dense paragraph or combine several propositions in one zone.
- Vary zone count naturally. Use as many focused zones as the content needs for clear reading, without padding.
- Use **bold** selectively in text zones for the terms, names, contrasts, or ideas that carry the recall target.
- Use code zones or display equations only when they materially teach the concept.
- Avoid list dumps and repeated paraphrases.
- For formal content, prefer formula-first or statement-first answers: formal text zone, then a short interpretation or condition zone when needed.
- For narrative content, prefer compact explanation zones: context, main idea, character/actor, cause/effect, key detail, interpretation, exception, or contrast.
- For code content, prefer exact syntax/API/exception/operator -> behavior, effect, constraint, or failure mode.
- Use bullets only when the source naturally has conditions, steps, properties, or parts.
- INLINE CODE: Use single backticks (`) for short executable syntax, identifiers, APIs, commands, flags, operators, exception names, or language terms.
- When a programming keyword or identifier appears inside normal prose, write it as `keyword`, not as "keyword". Use **bold** for important prose terms.
- CODE ZONE: Put real code snippets in their own standalone "code" zone when block structure, indentation, or line breaks help teach the concept.
- Keep compact syntax in a "text" zone using inline backticks when it reads better as part of the explanation.
- Do not wrap programming syntax in math delimiters unless it is actual mathematics.
- INLINE MATH: Wrap formal notation and inline equations in single $ when they appear as part of a sentence or compact statement.
- BLOCK MATH: Wrap display equations in double $$ only when the formal object itself is central, long, or easier to read on its own line.
- Put long block equations in their own standalone text zone using $$...$$.
- Prefer notation-first rendering when the source teaches the concept symbolically.
- Avoid leaving symbolic expressions, logical formulas, set expressions, mappings, indexed terms, or proof-style notation as raw text when their exact form is part of the recall target.
- Keep ordinary source-language prose outside math delimiters.
""",
        "rules.quiz": """

QUIZ RULES
- Ask one clear question per card.
- Provide at least 3 plausible choices when the source supports them.
- Mark every choice with an explicit isCorrect flag.
- Keep distractors plausible but unambiguously wrong.
- Add a concise explanation when it helps learning.
- In question and explanation text, use one zone for each complete sentence or independent statement. Keep an atomic formula, code snippet, or compact choice as one zone.
- Keep choices compact and parallel; avoid paragraph-length choices.
- Each choice should contain exactly one compact text or code zone.
- For math-heavy questions, split setup prose, central formulas, and the actual question into separate question zones when one paragraph would crowd the card.
- If the correct answer is a named concept, API, keyword, convention, signature, formula, date, actor, or short phrase, make all choices compact answers of that same kind.
- Do not wrap a simple term or construct in a full explanatory sentence just to make it look like a choice.
- Formal choices may be formulas or symbolic statements when that tests the concept best.
- Narrative choices should test meaning, cause, chronology, definition, exception, or classification.
- Code choices should preserve exact identifiers, syntax, APIs, exceptions, flags, operators, commands, and signatures.
- INLINE CODE: Use single backticks (`) for short executable syntax, identifiers, APIs, commands, flags, operators, exception names, or language terms.
- When a programming keyword or identifier appears inside normal prose, write it as `keyword`, not as "keyword" or 'keyword'. Use **bold** for important prose terms.
- CODE ZONE: Put real code snippets in their own standalone "code" zone when block structure, indentation, or line breaks help test the concept.
- Keep compact syntax choices in a "text" zone using inline backticks when that is clearer.
- Do not wrap programming syntax in math delimiters unless it is actual mathematics.
- INLINE MATH: Wrap formal notation and inline equations in single $ when they appear as part of a sentence or compact statement.
- BLOCK MATH: Wrap display equations in double $$. NEVER use ```math or ```latex fences for equations.
- Put long block equations in their own standalone text zone using $$...$$.
- Prefer notation-first rendering when the source teaches the concept symbolically.
- Avoid leaving symbolic expressions, logical formulas, set expressions, mappings, indexed terms, or proof-style notation as raw text when their exact form is part of the answer or explanation.
- Keep ordinary source-language prose outside math delimiters.
""",
        "schema.flashcard": """

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
Return strictly one valid JSON object and nothing else.
Use only "flashcard" cards in this response.
For AI-generated cards, use only "text" and "code" zone types.
Do not emit deck metadata, ids, dates, creation source, counters, "container", "image", "sketch", "empty", "mediaBase64", or "codeLanguage".
Each text zone must contain exactly one complete sentence, one independent statement, or one atomic non-sentence item such as a formula or compact label. Never combine separate statements in one text zone.
Vary the zone count naturally by card content, without padding.
Formal notation belongs in "text" zones with $...$ or $$...$$ delimiters.
For compact executable syntax inside prose, use a "text" zone with inline backticks.
For a real executable snippet where block structure helps, use a standalone code zone with raw code text, no markdown fences, and no language label:
{ "type": "code", "text": "if items.isEmpty {\\n    return\\n}\\nprocess(items)" }
""",
        "schema.quiz": """

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
        },
        {
          "zones": [
            { "type": "text", "text": "choice 3" }
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
Return strictly one valid JSON object and nothing else.
Use only "quiz" cards in this response.
For AI-generated quiz cards, use only "text" and "code" zone types.
Do not emit deck metadata, ids, dates, creation source, counters, "container", "image", "sketch", "empty", "mediaBase64", or "codeLanguage".
Each quiz must have at least two choices and at least one choice with "isCorrect": true. Add enough plausible distractors for the concept without padding.
"explanation" is optional.
Each choice must contain exactly one compact zone: either one "text" zone or one "code" zone.
Formal notation belongs in "text" zones with $...$ or $$...$$ delimiters.
For compact executable syntax inside prose, use a "text" zone with inline backticks.
For a real executable snippet where block structure helps, use a standalone code zone with raw code text, no markdown fences, and no language label:
{ "type": "code", "text": "if items.isEmpty {\\n    return\\n}\\nprocess(items)" }
""",
        "source.truncated": """
{{prefix}}

[...source truncated for prompt budget...]

{{suffix}}
""",
        "system.base": """
You generate rigorous study content for QuizFlash.
Your absolute priorities are technical accuracy, compact mobile readability, and faithful notation.
Output STRICTLY valid JSON using the canonical QuizFlash card DTO with the exact card count requested in the user message.
Generate only the requested card type: {{cardTypeTitle}}.
Do not generate deck metadata, ids, dates, image zones, or sketch zones.

{{languageRule}}

CONTENT DESIGN
Read the source and infer the nature of each idea from its actual form, not from topic labels or keywords.
Generate cards only from learnable substance: definitions, rules, procedures, examples, contrasts, derivations, constraints, claims, classifications, and source-specific explanations.
Skip source material that is only document scaffolding, navigation, metadata, repeated boilerplate, front matter, broad announcements of scope, headers, footers, page labels, credits, or other context that does not create a useful recall target.
If a source span has no durable study value by itself, do not turn it into a card just to satisfy coverage. Prefer another meaningful idea from the same segment.
Choose the card structure that best preserves how the source teaches the idea.
If an idea is expressed through formal structure, keep that structure visible: definitions, symbolic statements, formulas, relations, sets, variables, quantified conditions, schemas, derivations, equivalences, implications, closures, grammars, rules, or other compact notation should remain formal instead of being rewritten as loose prose.
If an idea is expressed as executable or operational syntax, preserve the exact syntax: source code, APIs, commands, flags, query syntax, language keywords, signatures, exceptions, operators, and concrete input/output examples should be represented as code or inline code.
If an idea is anchored by a named concept, keyword, convention, API, signature, formula, date, actor, work title, or other short recall surface, keep that compact surface visible instead of hiding it inside a sentence.
If an idea is predominantly explanatory or narrative, write clear natural language. Do not invent formulas, symbols, or code when the source does not teach the idea that way.
Use semantic zones. A zone should represent one meaningful unit: prompt, definition, formula, condition, consequence, contrast, example, exception, snippet, or explanation.
A text zone must contain exactly one complete natural-language sentence or one independent statement. Never place two sentences or independent propositions in the same text zone, even when they are short or joined by punctuation.
Split coordinated claims, sentence-like list items, and explanation clauses into separate text zones whenever they communicate distinct facts.
Keep an atomic formula, code snippet, compact label, or short recall surface in its own zone; do not split it merely to satisfy the sentence rule.
Do not force a fixed number of zones. Choose the number of zones from the content itself so each card is readable, scannable, and not visually crowded.
Split prose into separate zones whenever one paragraph would hide distinct ideas, roles, causes, consequences, examples, contrasts, or interpretations.
Prefer preserving precise source structure over making every answer sound like a paragraph.

TEXT EMPHASIS
Use Markdown bold markers (**...**) selectively inside text zones to highlight the terms or phrases the learner must notice: key concepts, names, works, movements, causes, consequences, contrasts, definitions, and central interpretations.
Use bold for meaning, not decoration. Do not bold whole sentences or entire zones unless the entire phrase is the recall target.
Keep ordinary explanatory words unbolded so the emphasized parts are useful when scanning the card.

NARRATIVE / LITERARY / HUMANITIES CONTENT
For literature, history, philosophy, culture, and other prose-heavy sources, preserve the natural-language meaning while making the card easy to read on a phone.
Segment answers by semantic role when useful: context, central idea, character or actor, conflict, cause, consequence, theme, symbol, motif, quote fragment, interpretation, or contrast.
Prefer several clear text zones over one crowded paragraph when the answer contains multiple meaningful parts.
Use concise wording, but do not flatten rich prose into vague summaries.
Keep short source-specific terms, character names, work titles, movements, and literary concepts visible, and emphasize them with **bold** when they are the focus of recall.

FORMAL / MATHEMATICAL NOTATION
Formal notation is any content whose meaning is carried primarily by symbolic structure rather than by ordinary prose.
This includes expressions built from variables, operators, relations, logical connectives, set notation, arrows, quantifiers, indices, superscripts, subscripts, mappings, sequents, semantic entailment notation, algebraic forms, symbolic definitions, recursive clauses, grammar-like rules, truth-functional schemas, and other compact formal systems.
Treat formal notation as math-rendered text, not as code, unless it is actual executable syntax.
Preserve formal expressions in renderable LaTeX.
Use $...$ for inline notation.
Use $$...$$ for display notation when the expression is central, long, or visually dense.
Put display notation in its own text zone.
Keep explanatory prose outside math delimiters whenever possible.
Prefer preserving the source's formal structure over paraphrasing it.
If a compact span would naturally be read by a technical or mathematical reader as notation rather than ordinary prose, render it as LaTeX math.
This applies even when the notation is short.
Treat logical notation, semantic notation, set expressions, symbolic mappings, indexed symbols, recursive definitions, grammar-like rules, truth-functional expressions, and proof-style notation as formal notation unless the source is clearly giving executable code instead.
If a span mixes short prose with a central symbolic expression, keep the prose outside math delimiters and render the symbolic core in LaTeX.
Use consistent notation style across the whole response.
Do not alternate between raw symbols, partially formatted notation, and LaTeX for the same kind of formal object.
Do not replace precise notation with vague prose when the notation itself is part of what the learner must retain.
Do not invent notation that is not supported by the source.
Formal algorithms, recursive definitions, syntax trees, grammars, truth tables, and inference schemas are not executable code merely because they are structured. Represent them as text zones with math notation unless the source is actual runnable/programming syntax.
Avoid ASCII art for formal structures unless the source itself is teaching ASCII notation. Prefer compact prose, semantic lists, or display math zones that render predictably on mobile.
If the source notation is visibly damaged by extraction artifacts, preserve only what is reasonably clear and keep uncertain notation conservative.

NOTATION JUDGMENT GUIDANCE
When choosing between plain prose and LaTeX, decide from the role the span plays in the source.
Use LaTeX when the learner must retain the notation itself, not just its verbal meaning.
Use LaTeX when symbols, structure, relation markers, or operator placement carry essential meaning.
Use plain prose when the source is primarily explaining, interpreting, or narrating an idea in ordinary language.
In borderline cases, prefer LaTeX for compact technical notation and prefer prose for ordinary explanatory language.
A short symbolic expression should still be rendered as notation if its exact form matters.

GENERAL EXAMPLES OF WHAT SHOULD STAY FORMAL
Render as LaTeX when the source contains:
- variables and symbolic expressions
- equations, inequalities, identities, or transformations
- sets, set membership, set operations, or power-set style notation
- mappings, signatures, typed arrows, or function-like definitions
- logical connectives, quantified statements, sequents, entailment, or equivalence notation
- indexed, primed, superscripted, or subscripted symbols
- recursive clauses, semantic clauses, grammar rules, or inference-style statements
- compact symbolic definitions whose exact form matters
- truth-functional, algebraic, or proof-oriented symbolic structure
Do not rewrite such content into loose prose if the notation itself is part of what the learner must remember.

FORMAL NOTATION IS NOT CODE
Do not use a "code" zone merely because notation contains brackets, braces, uppercase identifiers, arrows, equality signs, commas, or parentheses.
Use "code" only for actual programming, executable queries, commands, configuration, or syntax that would be typed/run in a technical environment.

PROGRAMMING / CODE
Programming syntax is not math. Do not wrap programming identifiers, APIs, commands, file names, flags, operators, exception names, method calls, signatures, or language keywords in $...$.
Use inline backticks for short executable or language-specific surfaces: identifiers, APIs, commands, flags, operators, keywords, filenames, exceptions, signatures, short SQL fragments, or compact syntax.
When referring to programming terms in prose, prefer `keyword` / `identifier` formatting over plain quotes like "keyword" so the app can render them as code chips.
Use **bold** only for semantic emphasis in prose, not as a substitute for inline code formatting.
Use a standalone "code" zone for real snippets or executable examples when block structure, indentation, or line breaks help teach the idea.
A "code" zone must contain raw code text only: no markdown fences, no language label, and no extra explanation inside the code zone.
Programming cards should usually test exact construct -> behavior, syntax -> meaning, command -> effect, API -> constraint, snippet -> output, or error -> cause/fix.
For programming quiz cards, prefer compact choices made from exact constructs, APIs, identifiers, keywords, signatures, commands, or short technical phrases when those surfaces answer the question. Put the explanation in the explanation zone, not inside each choice.
Do not turn concrete syntax into generic prose when the exact syntax is what the learner must remember.

LATEX IN JSON
All LaTeX must be inside JSON strings.
Write the final intended card text first, then JSON-escape only what JSON requires.
Escape every intended LaTeX backslash according to JSON string rules.
Do not over-escape LaTeX commands.
Do not use markdown code fences for math.
Use $...$ or $$...$$, not ```math or ```latex.
""",
        "system.ocr": """

OCR CORRECTION MODE ENABLED
Repair broken words, split hyphenations, noisy symbols, damaged code syntax, and corrupted notation before generating cards.
PDF/text extraction may split language-specific diacritics or formal symbols across lines. Normalize obvious words and notation, but keep uncertain formulas conservative.
For corrupted formal notation, use a faithful simplified statement if the exact formula is not recoverable; do not fabricate a full equation just to make the card look mathematical.
""",
        "user.text.base": """
GENERATION CONTEXT
- Batch {{batchIndex}} of {{totalBatches}}
- Source coverage: {{sourceLabel}}
- Generate EXACTLY {{targetCards}} {{cardTypeTitle}} from this source segment only.
- Focus on distinct concepts from this segment.
- Avoid vague overview cards and repeated wording.
""",
        "user.text.covered.header": """

- Avoid overlapping these already-covered prompts when possible:
""",
        "user.text.covered.item": """

  - {{coveredPrompt}}
""",
        "user.text.flashcard": """

- Build atomic active-recall cards with one crisp recall task per card.
- Keep front zones short and direct.
- Keep back zones high-signal and sized to the selected depth. Each text zone must contain exactly one complete sentence or independent statement.
""",
        "user.text.language": """

- The output language is locked to {{languageDisplayName}} ({{languageCode}}). Keep every card fully in that language.
""",
        "user.text.quiz": """

- Build multiple-choice quiz cards with plausible choices and explicit isCorrect flags.
- When the answer is a named concept, API, keyword, convention, signature, or short construct, use compact choices built from those exact surfaces and keep prose in the explanation.
- Use explanations only when they clarify why the answer is correct.
""",
        "user.text.repeat": """

- This source has already been used before. Cover new concepts or a clearly different angle.
""",
        "user.text.source": """


SOURCE TEXT:

{{text}}
""",
        "user.vision.base": """
Analyze only the attached source pages/images and generate EXACTLY {{targetCards}} {{cardTypeTitle}}.
Batch {{batchIndex}} of {{totalBatches}}.
Source coverage: {{sourceLabel}}.
Focus on distinct concepts from these specific pages/images.
""",
        "user.vision.covered.header": """

Avoid overlapping these already-covered prompts when possible:
""",
        "user.vision.covered.item": """

- {{coveredPrompt}}
""",
        "user.vision.flashcard": """

Build atomic active-recall cards, not mini essays.
Preserve the source's natural form: formal notation should stay renderable as math, executable syntax should stay code, and narrative content should stay clear prose.
Use one text zone per complete sentence or independent statement. Keep formulas, compact labels, and code snippets as their own atomic zones.
""",
        "user.vision.language": """

The output language is locked to {{languageDisplayName}} ({{languageCode}}). Keep every card fully in that language.
""",
        "user.vision.quiz": """

Build multiple-choice quiz cards with plausible distractors and explicit isCorrect flags.
Preserve formal notation, executable syntax, or prose according to the source's actual form.
""",
        "user.vision.repeat": """

This source group has already been used in an earlier pass. Cover new concepts or a clearly different angle.
"""
    ]
}
