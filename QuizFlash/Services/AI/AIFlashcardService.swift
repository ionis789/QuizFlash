import Foundation
import UIKit // Required for UIImage – image pipeline only, no UI components used

// =============================================================================
// MARK: - AI Service Errors
// =============================================================================

public enum AIServiceError: LocalizedError {
    case invalidAPIKey
    case networkError
    case invalidResponse
    case parsingFailed
    case rateLimitExceeded
    case timeout
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAPIKey: return "Invalid API key."
        case .networkError: return "Network error."
        case .invalidResponse: return "Invalid response."
        case .parsingFailed: return "Parsing failed."
        case .rateLimitExceeded: return "Too many requests. Try again later."
        case .timeout: return "Timeout – no response from the server."
        case .unknown(let msg): return msg
        }
    }
}

// =============================================================================
// MARK: - Response DTO
// =============================================================================

/// The structured JSON contract between GPT and the app.
/// GPT returns zones as arrays — each element becomes one visual zone block.
private struct FlashcardResponseDTO: Codable {
    struct CardDTO: Codable {
        let question_zones: [String]?
        let question: String? // Fallback if question_zones are intepreted as question by AI
        let answer_zones: [String]
        let answer: [String]? // Fallback

        var resolvedQuestionZones: [String] {
            if let qz = question_zones { return qz }
            if let q = question { return [q] }
            return ["?"]
        }
    }
    let flashcards: [CardDTO]?
}

// =============================================================================
// MARK: - AI Flashcard Service
// =============================================================================

public final class AIFlashcardService {

    // -------------------------------------------------------------------------
    // MARK: - Configuration
    // -------------------------------------------------------------------------

    private let apiKey: String
    private let apiEndpoint = "https://api.deepseek.com/chat/completions"
    private let textModel = "deepseek-chat"
    private let visionModel = "deepseek-chat"
    private let session: URLSession
    private let maxCharsPerChunk = 12_000

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------

    public init(apiKey: String) {
        self.apiKey = apiKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config)
    }

    // -------------------------------------------------------------------------
    // MARK: - Public Entry Points
    // -------------------------------------------------------------------------

    /// Generates flashcards from a PDF file.
    ///
    /// - Parameters:
    ///   - pdfURL: The local file URL of the PDF document.
    ///   - targetCards: The desired number of flashcards to generate.
    /// - Returns: An array of `AIFlashcard` values.
    /// - Throws: `AIServiceError` if extraction, network communication, or parsing fails.
    public func generateFlashcards(from pdfURL: URL, targetCards: Int) async throws -> [AIFlashcard] {
        let result = await DocumentTextExtractor.extract(from: pdfURL)
        return try await route(result: result, targetCards: targetCards)
    }

    /// Generates flashcards from a collection of images.
    ///
    /// - Parameters:
    ///   - images: An array of `UIImage` values (camera captures, scanned pages, etc.).
    ///   - targetCards: The desired number of flashcards to generate.
    /// - Returns: An array of `AIFlashcard` values.
    /// - Throws: `AIServiceError` if network communication or parsing fails.
    public func generateFlashcards(from images: [UIImage], targetCards: Int) async throws -> [AIFlashcard] {
        let result = await DocumentTextExtractor.extract(from: images)
        return try await route(result: result, targetCards: targetCards)
    }

    /// Generates flashcards from a plain-text string.
    ///
    /// - Parameters:
    ///   - text: The source text content.
    ///   - targetCards: The desired number of flashcards to generate.
    /// - Returns: An array of `AIFlashcard` values.
    /// - Throws: `AIServiceError` if network communication or parsing fails.
    public func generateFlashcards(fromText text: String, targetCards: Int) async throws -> [AIFlashcard] {
        return try await dispatchText(text, targetCards: targetCards, needsOCRCorrection: false)
    }

    // -------------------------------------------------------------------------
    // MARK: - Routing
    // -------------------------------------------------------------------------

    private func route(result: ExtractionResult, targetCards: Int) async throws -> [AIFlashcard] {
        switch result.method {
        case .pdfKit, .visionOCR:
            guard let text = result.text, !text.isEmpty else { throw AIServiceError.parsingFailed }
            return try await dispatchText(text, targetCards: targetCards, needsOCRCorrection: result.needsOCRCorrection)
        case .rawImages:
            guard let images = result.images, !images.isEmpty else { throw AIServiceError.parsingFailed }
            let messages = buildVisionMessages(images: images, targetCards: targetCards)
            return try await sendRequest(messages: messages, model: visionModel)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Text Dispatch (chunking)
    // -------------------------------------------------------------------------

    private func dispatchText(
        _ text: String,
        targetCards: Int,
        needsOCRCorrection: Bool
    ) async throws -> [AIFlashcard] {
        let chunks = splitIntoChunks(text)

        if chunks.count == 1 {
            let messages = buildTextMessages(
                text: text,
                targetCards: targetCards,
                needsOCRCorrection: needsOCRCorrection
            )
            return try await sendRequest(messages: messages, model: textModel)
        }

        let distribution = distributeCards(targetCards, across: chunks.count)

        return try await withThrowingTaskGroup(of: [AIFlashcard].self) { group in
            for (i, chunk) in chunks.enumerated() {
                let cardsForChunk = distribution[i]
                guard cardsForChunk > 0 else { continue }
                group.addTask {
                    let messages = self.buildTextMessages(
                        text: chunk,
                        targetCards: cardsForChunk,
                        needsOCRCorrection: needsOCRCorrection
                    )
                    return try await self.sendRequest(messages: messages, model: self.textModel)
                }
            }
            var all: [AIFlashcard] = []
            for try await cards in group { all.append(contentsOf: cards) }
            return all
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Chunking Helpers
    // -------------------------------------------------------------------------

    private func splitIntoChunks(_ text: String) -> [String] {
        guard text.count > maxCharsPerChunk else { return [text] }
        let pageSeparator = "\n\n--- Next page ---\n\n"
        let pages = text.components(separatedBy: pageSeparator)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard pages.count > 1 else { return splitBySize(text) }

        var chunks: [String] = []
        var current = ""
        for page in pages {
            if current.isEmpty {
                current = page
            } else if current.count + page.count + pageSeparator.count > maxCharsPerChunk {
                chunks.append(current)
                current = page
            } else {
                current += pageSeparator + page
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private func splitBySize(_ text: String) -> [String] {
        var chunks: [String] = []
        var startIndex = text.startIndex
        while startIndex < text.endIndex {
            let endOffset = min(maxCharsPerChunk, text.distance(from: startIndex, to: text.endIndex))
            var endIndex = text.index(startIndex, offsetBy: endOffset)
            if endIndex < text.endIndex {
                let lookback = text[startIndex..<endIndex]
                if let lastBreak = lookback.rangeOfCharacter(from: .newlines, options: .backwards) {
                    endIndex = lastBreak.upperBound
                }
            }
            chunks.append(String(text[startIndex..<endIndex]))
            startIndex = endIndex
        }
        return chunks
    }

    private func distributeCards(_ total: Int, across count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var result = Array(repeating: total / count, count: count)
        for i in 0..<(total % count) { result[i] += 1 }
        return result
    }

    // -------------------------------------------------------------------------
    // MARK: - Message Builders
    // -------------------------------------------------------------------------

    nonisolated private func buildTextMessages(
        text: String,
        targetCards: Int,
        needsOCRCorrection: Bool
    ) -> [[String: Any]] {
        [
            ["role": "system", "content": systemPrompt(targetCards: targetCards, isOCR: needsOCRCorrection)],
            ["role": "user", "content": "SOURCE TEXT:\n\n\(text)"]
        ]
    }

    nonisolated private func buildVisionMessages(images: [UIImage], targetCards: Int) -> [[String: Any]] {
        var userContent: [[String: Any]] = [
            ["type": "text", "text": "Analyze all pages carefully and generate flashcards based on their content."]
        ]
        for image in images {
            guard let data = image.jpegData(compressionQuality: 0.7) else { continue }
            userContent.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())", "detail": "auto"]
            ])
        }
        return [
            ["role": "system", "content": systemPrompt(targetCards: targetCards, isOCR: false)],
            ["role": "user", "content": userContent]
        ]
    }

    // =========================================================================
    // MARK: - System Prompt
    // =========================================================================
    //
    // DESIGN PRINCIPLES:
    //   • GPT returns zones as string arrays, not a single block of text
    //   • Each array element = one visual zone block in the app
    //   • Clear splitting rules: when to use 1 zone vs multiple
    //   • Explicit LaTeX escaping rules with CONCRETE before/after examples
    //   • Math always in $...$ or $$...$$, never raw
    //   • The LaTeX escaping section uses a concrete "LOOK AT THIS OUTPUT"
    //     style to prevent GPT from over-thinking the escaping.
    //
    // =========================================================================

    nonisolated private func systemPrompt(targetCards: Int, isOCR: Bool) -> String {
        var prompt = #"""
        You are a rigorous University Professor AI specialized in generating elite, in-depth "Active Recall" flashcards.
        Your absolute priority is TECHNICAL DEPTH, ACCURACY, and HIGH READABILITY.
        
        Output STRICTLY valid JSON with EXACTLY \#(targetCards) flashcards.
        
        ═══════════════════════════════════════════════════════
        REQUIRED JSON SCHEMA (CRITICAL - DO NOT ALTER)
        ═══════════════════════════════════════════════════════
        You MUST output valid JSON matching EXACTLY this schema:
        {
          "flashcards": [
            {
              "question_zones": ["string1", "string2"],
              "answer_zones": ["string1", "string2", "string3"]
            }
          ]
        }
        STRICT RULE: NEVER use the key "question" or "answer". You MUST use EXACTLY "question_zones" and "answer_zones" as ARRAYS of strings.
        
        ═══════════════════════════════════════════════════════
        LANGUAGE RULE (CRITICAL)
        ═══════════════════════════════════════════════════════
        You MUST EXACTLY match the language of the source text. If the source text is in language X, the flashcards MUST be written in language X. Do not translate concepts to English.
        
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
        - INLINE MATH: Wrap every math symbol, variable, and inline equation in single $. Example: "$v \in V$", "$\dim(V)$".
        - BLOCK MATH: Wrap display equations in double $$. NEVER use ```math or ```latex fences for equations.
        - BLOCK CODE: Triple-backtick code blocks MUST be in their own standalone string in the array.
        
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

        if isOCR {
            prompt += """
        
        ═══════════════════════════════════════════════════════
        OCR CORRECTION MODE ENABLED
        ═══════════════════════════════════════════════════════
        Repair corrupted code syntax, broken LaTeX, and misrecognized symbols (e.g., 0/O, 1/l, alpha/a). Preserve strict technical correctness.
        """
        }

        return prompt
    }

    // -------------------------------------------------------------------------
    // MARK: - Network
    // -------------------------------------------------------------------------

    private func sendRequest(messages: [[String: Any]], model: String) async throws -> [AIFlashcard] {
        guard let url = URL(string: apiEndpoint) else { throw AIServiceError.networkError }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "response_format": ["type": "json_object"],
            "temperature": 0.2
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }
            guard (200...299).contains(http.statusCode) else {
                throw AIServiceError.unknown("OpenAI HTTP \(http.statusCode)")
            }
            let content = try parseResponseContent(from: data)
            return try decodeFlashcards(from: content)
        } catch let e as AIServiceError {
            throw e
        } catch {
            throw AIServiceError.networkError
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Response Parsing
    // -------------------------------------------------------------------------

    private func parseResponseContent(from data: Data) throws -> String {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
            else {
            throw AIServiceError.parsingFailed
        }
        return content
    }

    private func decodeFlashcards(from jsonString: String) throws -> [AIFlashcard] {
        // Strip markdown code fences if present (shouldn't happen with json_object mode, but defensive)
        print("═══════════════════════════════════")
        print("📦 RAW GPT JSON:")
        print(jsonString)
        print("═══════════════════════════════════")
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
            let dto = try JSONDecoder().decode(FlashcardResponseDTO.self, from: data)
            guard let cards = dto.flashcards, !cards.isEmpty else {
                throw AIServiceError.parsingFailed
            }

            return cards.map { card in
                // Use resolvedQuestionZones instead of question_zones for robust fallback handling
                let questionZones = card.resolvedQuestionZones
                    .map { AIZoneParser.sanitizeLatex($0) }
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

                let answerZones = card.answer_zones
                    .map { AIZoneParser.sanitizeLatex($0) }
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

                let question = questionZones.joined(separator: AIZoneParser.zoneDelimiter)
                let answer = answerZones.joined(separator: AIZoneParser.zoneDelimiter)

                return AIFlashcard(
                    id: UUID(),
                    question: question.isEmpty ? card.resolvedQuestionZones.joined(separator: " ") : question,
                    answer: answer.isEmpty ? card.answer_zones.joined(separator: " "): answer
                )
            }
        } catch {
            print("❌ JSON DECODE ERROR: \(error)")
            print("📦 RAW JSON FROM GPT:\n\(clean)")
            throw AIServiceError.parsingFailed
        }
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
    private func fixLatexEscaping(in jsonString: String) -> String {
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
