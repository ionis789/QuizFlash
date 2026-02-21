import Foundation
import UIKit

// =============================================================================
// MARK: - Errors
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
        case .invalidAPIKey:     return "API key invalid sau lipsă."
        case .networkError:      return "Eroare de rețea. Verifică conexiunea."
        case .invalidResponse:   return "Răspuns invalid de la serverul AI."
        case .parsingFailed:     return "Nu am putut procesa răspunsul AI."
        case .rateLimitExceeded: return "Prea multe request-uri. Așteaptă."
        case .timeout:           return "Timeout. Încearcă cu mai puține pagini."
        case .unknown(let msg):  return msg
        }
    }
}

// =============================================================================
// MARK: - DTO
// =============================================================================

private struct FlashcardResponseDTO: Codable {
    struct CardDTO: Codable { let question: String; let answer: String }
    let flashcards: [CardDTO]?
}

// =============================================================================
// MARK: - AIFlashcardService
// =============================================================================

public final class AIFlashcardService {

    private let apiKey: String
    private let apiEndpoint = "https://api.openai.com/v1/chat/completions"
    private let textModel   = "gpt-4o-mini"
    private let visionModel = "gpt-4o"
    private let session: URLSession

    // Câte caractere trimitem per chunk.
    // La ~4 chars/token, 12.000 chars ≈ 3.000 tokens → lasă loc pentru răspuns.
    // Pentru un PDF de 50 pag (~50.000 chars) rezultă ~4-5 chunks procesate în paralel.
    private let maxCharsPerChunk = 12_000

    public init(apiKey: String) {
        self.apiKey = apiKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 180
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config)
    }

    // =========================================================================
    // MARK: - Public API
    // =========================================================================

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

    // =========================================================================
    // MARK: - Routing
    // =========================================================================

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

    // =========================================================================
    // MARK: - Smart Chunking
    //
    // Pentru documente lungi (cursuri de 50+ pagini), GPT devine "leneș" și
    // generează carduri superficiale dacă vede tot textul dintr-o dată.
    // Soluția: împărțim textul în chunk-uri de max 12k chars și procesăm
    // în PARALEL — la fel de rapid, dar carduri mult mai profunde.
    // =========================================================================

    private func dispatchText(
        _ text: String,
        targetCards: Int,
        needsOCRCorrection: Bool
    ) async throws -> [AIFlashcard] {

        let chunks = splitIntoChunks(text)

        if chunks.count == 1 {
            // Document scurt — un singur request
            let messages = buildTextMessages(
                text: text,
                targetCards: targetCards,
                needsOCRCorrection: needsOCRCorrection
            )
            return try await sendRequest(messages: messages, model: textModel)
        }

        // Document lung — requests paralele per chunk
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

    /// Împarte textul la granițele paginilor (separator generat de DocumentTextExtractor).
    /// Dacă textul nu are separatori, cade pe împărțire după număr de caractere.
    private func splitIntoChunks(_ text: String) -> [String] {
        guard text.count > maxCharsPerChunk else { return [text] }

        let pageSeparator = "\n\n--- Pagina următoare ---\n\n"
        let pages = text.components(separatedBy: pageSeparator)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard pages.count > 1 else {
            return splitBySize(text)
        }

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

            // Taiem la un spațiu/newline pentru a nu rupe cuvinte
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

    /// Distribuie N carduri pe M chunk-uri, proporțional cu mărimea chunk-ului.
    private func distributeCards(_ total: Int, across count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var result = Array(repeating: total / count, count: count)
        let remainder = total % count
        for i in 0..<remainder { result[i] += 1 }
        return result
    }

    // =========================================================================
    // MARK: - Message Builders
    // =========================================================================

    private func buildTextMessages(
        text: String,
        targetCards: Int,
        needsOCRCorrection: Bool
    ) -> [[String: Any]] {
        [
            ["role": "system", "content": systemPrompt(targetCards: targetCards, isOCR: needsOCRCorrection)],
            ["role": "user",   "content": "SOURCE TEXT:\n\n\(text)"]
        ]
    }

    private func buildVisionMessages(images: [UIImage], targetCards: Int) -> [[String: Any]] {
        var userContent: [[String: Any]] = [
            ["type": "text", "text": "Analyze all pages and generate flashcards."]
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
            ["role": "user",   "content": userContent]
        ]
    }

    // =========================================================================
    // MARK: - System Prompt
    //
    // Principii:
    // - "CONCISE" se aplică la explicații textuale, NU la cod
    // - Codul sursă trebuie reprodus COMPLET, niciodată trunchiat
    // - Cardurile despre programare trebuie să testeze înțelegerea profundă
    //   (de ce funcționează, ce se întâmplă în memorie, corner cases)
    // =========================================================================

    private func systemPrompt(targetCards: Int, isOCR: Bool) -> String {
        var prompt = """
        You are an expert educational tutor creating high-quality "Active Recall" flashcards.
        Your goal is to capture the DEEPEST, most TESTABLE knowledge from the source material.

        CRITICAL RULES:

        1. Generate EXACTLY \(targetCards) flashcards.
        2. LANGUAGE: Match the source text language EXACTLY.
        3. DEPTH OVER BREADTH: Prefer deep, specific questions over shallow definitions.
           - BAD: "What is a class?" → too shallow
           - GOOD: "What is the difference between a class and an object in Java?"
           - GOOD: "What happens in memory when you write `new Animal()`?"
           - GOOD: "Why must a Java constructor have the same name as the class?"

        4. ANSWERS — Two modes depending on content:

           MODE A — CONCEPTUAL (text, theory, history, math):
           Answers must be direct and concise. No filler words.
           BAD: "Paris is the capital of France, a beautiful city known for the Eiffel Tower."
           GOOD: "Paris."

           MODE B — CODE / TECHNICAL (when source has code examples):
           Answers MUST include the COMPLETE, RUNNABLE code example.
           NEVER truncate code. NEVER write "..." inside code.
           NEVER summarize code — show it fully.
           Code blocks use this EXACT format (triple backtick + language tag):
           ```java
           public class Animal {
               private String name;
               public Animal(String name) { this.name = name; }
               public String getName() { return name; }
           }
           ```

        5. CODE QUESTIONS — Ask about what you can actually test with code:
           - "Write the Java code for a class Animal with a private field 'name' and a constructor."
           - "What does the `private` keyword do in Java? Give an example."
           - "How do you instantiate an object from a class in Java?"
           - "What is printed by this code: [code snippet]?"

        6. MATH & LATEX:
           - Inline math: $x^2 + y^2$
           - Block/display math: $$\\sum_{i=0}^{n} x_i$$
           - Standard LaTeX commands only: \\varepsilon, \\alpha, \\in, \\cup, etc.
           - NEVER wrap plain text in $. Only actual math inside $.

        7. QUESTIONS format:
           - Must end with "?" OR start with "Write/Show/Explain/Define:"
           - Never split a sentence in half.

        8. OUTPUT: Strict JSON only. No markdown, no preamble.
           {"flashcards": [{"question": "...", "answer": "..."}, ...]}

        GOOD EXAMPLE — Code card:
        {"question": "Write the Java class Animal with a private String field 'name' and a public getter.",
         "answer": "```java\\npublic class Animal {\\n    private String name;\\n\\n    public Animal(String name) {\\n        this.name = name;\\n    }\\n\\n    public String getName() {\\n        return this.name;\\n    }\\n}\\n```"}

        GOOD EXAMPLE — Memory/concept card:
        {"question": "What happens in JVM memory when you execute `Animal a = new Animal(\\"Rex\\")`?",
         "answer": "A new object is allocated on the **heap**. The variable `a` (on the **stack**) holds a reference (pointer) to that heap object, not the object itself."}

        GOOD EXAMPLE — Math card:
        {"question": "How is the Kleene star $L^*$ defined?",
         "answer": "$$L^* = \\\\bigcup_{n \\\\geq 0} L^n$$ where $L^0 = \\\\{\\\\varepsilon\\\\}$ and $L^{n+1} = L^n \\\\cdot L$."}
        """

        if isOCR {
            prompt += """

        9. OCR CORRECTION: Source was extracted via OCR — may have typos or garbled chars.
           Infer correct meaning from context. Output grammatically correct, accurate text.
        """
        }

        return prompt
    }

    // =========================================================================
    // MARK: - Network
    // =========================================================================

    private func sendRequest(messages: [[String: Any]], model: String) async throws -> [AIFlashcard] {
        guard let url = URL(string: apiEndpoint) else { throw AIServiceError.networkError }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json",  forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model":           model,
            "messages":        messages,
            "response_format": ["type": "json_object"],
            "temperature":     0.2   // Consistență mare → format JSON stabil
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }

            if !(200...299).contains(http.statusCode) {
                if http.statusCode == 429 { throw AIServiceError.rateLimitExceeded }
                let msg = parseOpenAIError(from: data) ?? "HTTP \(http.statusCode)"
                throw AIServiceError.unknown("OpenAI: \(msg)")
            }

            let content = try parseResponseContent(from: data)

            #if DEBUG
            print("🤖 AI [\(model)] \(content.count) chars")
            print(content.prefix(400))
            #endif

            return try decodeFlashcards(from: content)

        } catch let e as AIServiceError { throw e
        } catch let e as URLError where e.code == .timedOut { throw AIServiceError.timeout
        } catch let e as URLError { print("URLError: \(e)"); throw AIServiceError.networkError
        } catch { throw error }
    }

    private func parseOpenAIError(from data: Data) -> String? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let err = j["error"] as? [String: Any],
              let msg = err["message"] as? String else { return nil }
        return msg
    }

    private func parseResponseContent(from data: Data) throws -> String {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = j["choices"] as? [[String: Any]],
              let first   = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else { throw AIServiceError.parsingFailed }
        return content
    }

    private func decodeFlashcards(from jsonString: String) throws -> [AIFlashcard] {
        var clean = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```") {
            clean = clean
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```",     with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = clean.data(using: .utf8) else { throw AIServiceError.parsingFailed }

        let dto = try JSONDecoder().decode(FlashcardResponseDTO.self, from: data)
        guard let cards = dto.flashcards, !cards.isEmpty else {
            throw AIServiceError.unknown("Format neașteptat: \(String(clean.prefix(120)))")
        }
        return cards.map { AIFlashcard(id: UUID(), question: $0.question, answer: $0.answer) }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
