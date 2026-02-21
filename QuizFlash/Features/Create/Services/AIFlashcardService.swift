import Foundation
import UIKit

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
        case .invalidAPIKey: return "API key invalid."
        case .networkError: return "Eroare rețea."
        case .invalidResponse: return "Răspuns invalid."
        case .parsingFailed: return "Procesare eșuată."
        case .rateLimitExceeded: return "Prea multe request-uri."
        case .timeout: return "Timeout."
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
        let question: String? // Fallback dacă GPT folosește 'question' ca string
        let answer_zones: [String]

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

//    private let apiKey: String
//    private let apiEndpoint = "https://api.openai.com/v1/chat/completions"
//    private let textModel = "gpt-4o-mini"
//    private let visionModel = "gpt-4o"
//    private let session: URLSession
//    private let maxCharsPerChunk = 12_000
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

    func generateFlashcards(from pdfURL: URL, targetCards: Int) async throws -> [AIFlashcard] {
        let result = await DocumentTextExtractor.extract(from: pdfURL)
        return try await route(result: result, targetCards: targetCards)
    }

    func generateFlashcards(from images: [UIImage], targetCards: Int) async throws -> [AIFlashcard] {
        let result = await DocumentTextExtractor.extract(from: images)
        return try await route(result: result, targetCards: targetCards)
    }

    func generateFlashcards(fromText text: String, targetCards: Int) async throws -> [AIFlashcard] {
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
        let pageSeparator = "\n\n--- Pagina următoare ---\n\n"
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

    private func buildTextMessages(
        text: String,
        targetCards: Int,
        needsOCRCorrection: Bool
    ) -> [[String: Any]] {
        [
            ["role": "system", "content": systemPrompt(targetCards: targetCards, isOCR: needsOCRCorrection)],
            ["role": "user", "content": "SOURCE TEXT:\n\n\(text)"]
        ]
    }

    private func buildVisionMessages(images: [UIImage], targetCards: Int) -> [[String: Any]] {
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
    //   • Explicit LaTeX escaping rules with working examples
    //   • Math always in $...$ or $$...$$, never raw
    //
    // =========================================================================

    private func systemPrompt(targetCards: Int, isOCR: Bool) -> String {
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
            - INLINE CODE: Use single backticks (`) generously for short syntax, class names, or specific technical terms (e.g., `new`, `String`).
            - INLINE MATH (CRITICAL): You MUST wrap EVERY mathematical variable, set, function, and equation in single $. NEVER use raw unicode characters for math (e.g., do NOT write α, ∈, or β as text). You MUST use LaTeX (e.g., $\alpha$, $\in$, $\beta$). Example: "$v \in V$", "$\dim(V) = \dim(W)$".
            - BLOCK MATH (CRITICAL): Block equations MUST be wrapped in double $$. NEVER use markdown code fences (like ```math or ```latex) for equations. Code fences are STRICTLY for programming languages.
            - BLOCK CODE: Triple-backtick code blocks (```) MUST be in their own standalone string in the array. NEVER combine introductory text and a ``` code block in the same string.
            - JSON ESCAPING: Double escape ALL backslashes for LaTeX (e.g., \\frac, \\notin, \\bullet) and escape double quotes (\").
        """#

        if isOCR {
            prompt += """

        ═══════════════════════════════════════════════════════
        OCR CORRECTION MODE ENABLED
        ═══════════════════════════════════════════════════════
        Repair corrupted code syntax, broken LaTeX, and misrecognized symbols (e.g., 0/O, 1/l, \\alpha / a). Preserve strict technical correctness.
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
        // Strip markdown code fences if present (shouldn't happen with json_object mode, but safe)````≥≤`
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
                // Folosim resolvedQuestionZones în loc de question_zones
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
    // MARK: - LaTeX JSON Escape Fixer
    // -------------------------------------------------------------------------

    private func fixLatexEscaping(in jsonString: String) -> String {
            // Am adăugat bullet, vdots, beta, bmatrix pentru protecție maximă!
            let problematicCommands = [
                "notin", "nabla", "nu", "ne", "neg", "ni", "natural", "nRightarrow", "nrightarrow", "nexists",
                "text", "textbackslash", "theta", "tau", "to", "times", "tilde", "tan", "triangle", "textbf", "textit",
                "rightarrow", "rangle", "rho", "Rightarrow", "rbrace", "rceil", "rfloor", "rm",
                "beta", "bot", "bar", "bigcap", "bigcup", "bigsqcup", "biguplus", "bigvee", "bigwedge", "bf", "begin", "bmatrix", "mathbb", "mathbf", "bullet", "vdots",
                "frac", "forall", "frown", "flat"
            ].joined(separator: "|")
            
            let pattern = "(?<!\\\\)\\\\(\(problematicCommands))\\b"
            
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                return jsonString
            }
            
            let range = NSRange(jsonString.startIndex..., in: jsonString)
            return regex.stringByReplacingMatches(in: jsonString, options: [], range: range, withTemplate: "\\\\\\\\$1")
        }
}
