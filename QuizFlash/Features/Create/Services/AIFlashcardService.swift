import Foundation
import UIKit

public enum AIServiceError: LocalizedError {
    case invalidAPIKey, networkError, invalidResponse, parsingFailed, rateLimitExceeded, timeout, unknown(String)
    public var errorDescription: String? {
        switch self {
        case .invalidAPIKey: return "AI API key is not configured or invalid."
        case .networkError: return "Eroare de rețea. Verifică conexiunea la internet."
        case .invalidResponse: return "Răspuns invalid de la serverul AI."
        case .parsingFailed: return "Failed to parse AI response. Please try again."
        case .rateLimitExceeded: return "Prea multe request-uri. Te rog așteaptă câteva momente."
        case .timeout: return "Timpul de așteptare a expirat. Încearcă Fast OCR."
        case .unknown(let message): return "\(message)" // Afișează eroarea exactă pe ecran
        }
    }
}

private struct AIGenerationResponseDTO: Codable {
    struct CardDTO: Codable { let question: String; let answer: String }
    let flashcards: [CardDTO]? // Făcut opțional pentru a prinde erorile fin
}

@MainActor
public final class AIFlashcardService {
    // ⚠️ Asigură-te că îți gestionezi cheia corect în producție
    private let apiKey = "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"
    private let apiEndpoint = "https://api.openai.com/v1/chat/completions"
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180
        self.session = URLSession(configuration: config)
    }

    // MARK: - METODA 1: VISION (Trimite imagini)
    func generateFlashcards(from images: [UIImage], targetCards: Int) async throws -> [AIFlashcard] {
        let batchSize = 8
        let batches = images.chunked(into: batchSize)
        var allFlashcards: [AIFlashcard] = []

        for (index, batch) in batches.enumerated() {
            let cardsForThisBatch = calculateCardsForBatch(totalRequested: targetCards, totalBatches: batches.count, currentBatchIndex: index)
            if cardsForThisBatch > 0 {
                let content = buildMultimodalContent(from: batch, requestedCards: cardsForThisBatch)
                let cards = try await sendRequest(content: content)
                allFlashcards.append(contentsOf: cards)
            }
        }
        return allFlashcards
    }

    // MARK: - METODA 2: TEXT/OCR (Ultra Rapid)
    func generateFlashcards(fromText text: String, targetCards: Int) async throws -> [AIFlashcard] {
        let content = buildTextContent(from: text, requestedCards: targetCards)
        return try await sendRequest(content: content)
    }

    // MARK: - PROMPT-URI REVIZUITE
    private func getSystemPrompt(requestedCards: Int, isOCR: Bool) -> String {
        var prompt = """
            You are an expert educational tutor creating study materials for "Active Recall".

            CRITICAL RULES:
            1. Read the provided document carefully. Identify the core concepts, events, formulas, code snippets, or definitions.
            2. Generate EXACTLY \(requestedCards) flashcards.
            3. LANGUAGE MATCHING: You MUST use the EXACT SAME LANGUAGE as the main text provided.
            4. CONTEXT COMPLETION: If the text is fragmented, use your expert knowledge to fill in the gaps so the flashcard makes complete sense factually.
            
            5. CONCISE & PRECISE ANSWERS (CRITICAL): Answers MUST be direct, strictly to the point, and highly accurate. ABSOLUTELY NO FLUFF, no filler words, and no unnecessarily long explanations. If a short answer is sufficient, keep it short. Give the exact information needed, nothing more.
            
            6. QUESTION FORMAT: The "question" MUST be a direct interrogative sentence ending with a question mark (?), or a clear "Define/Explain: X" prompt. Do NOT split sentences in half.
            
            7. MATH/LATEX: You MUST use LaTeX for math formulas, equations, or scientific symbols.
               - Use single `$` for inline math (e.g., the variable $x$ or \\varepsilon).
               - Use double `$$` for block math.
               - ABSOLUTELY DO NOT wrap regular text, sentences, paragraphs, or bullet points in `$`. 
               - WRONG SENTENCE: $The capital of France is Paris.$
               - CORRECT SENTENCE: The capital of France is Paris.
               - WRONG LIST ITEM: - $The tree nodes are labeled with $T$.$
               - CORRECT LIST ITEM: - The tree nodes are labeled with $T$.
               
            8. OUTPUT FORMAT: Output MUST be a strict JSON object with a single root key "flashcards", containing an array of {"question": "...", "answer": "..."}.

            BAD EXAMPLE (Too much fluff / Unnecessary elaboration):
            {"question": "What is the capital of France?", "answer": "The capital of France is Paris. Paris is a very beautiful city known for the Eiffel Tower and it has been the capital for a very long time."}

            GOOD EXAMPLE 1 (Concise & Precise Math):
            {"question": "How is the Kleene star $L^*$ defined?", "answer": "The Kleene star $L^*$ is the union of all powers of a language $L$: $$L^* = \\bigcup_{n\\ge 0} L^n$$."}

            GOOD EXAMPLE 2 (Concise History):
            {"question": "What were the primary causes of the Daco-Roman wars (101-106 AD)?", "answer": "The Roman Empire needed to secure its borders against Dacian raids, and Emperor Trajan wanted to control Dacia's rich gold mines."}
            """

        if isOCR {
            prompt += "\n\n9. OCR CORRECTION: The provided text is extracted via OCR and may contain typos or garbled characters. Infer the correct meaning and output grammatically correct text."
        }

        return prompt
    }

    // Am structurat requestul mai profesionist, separând System Prompt-ul de User Text
    private func buildMultimodalContent(from images: [UIImage], requestedCards: Int) -> [[String: Any]] {
        var messages: [[String: Any]] = [
            ["role": "system", "content": getSystemPrompt(requestedCards: requestedCards, isOCR: false)]
        ]

        var userContent: [[String: Any]] = []
        for image in images {
            if let jpegData = image.jpegData(compressionQuality: 0.6) {
                userContent.append([
                    "type": "image_url",
                    "image_url": [
                        "url": "data:image/jpeg;base64,\(jpegData.base64EncodedString())",
                        "detail": "auto"
                    ]
                ])
            }
        }

        messages.append(["role": "user", "content": userContent])
        return messages
    }

    private func buildTextContent(from text: String, requestedCards: Int) -> [[String: Any]] {
        return [
            ["role": "system", "content": getSystemPrompt(requestedCards: requestedCards, isOCR: true)],
            ["role": "user", "content": "SOURCE OCR TEXT:\n\n" + text]
        ]
    }

    // MARK: - API CALL
    private func sendRequest(content: [[String: Any]]) async throws -> [AIFlashcard] {
        var request = URLRequest(url: URL(string: apiEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            // AM CORECTAT MODELUL AICI (gpt-4o-mini este varianta corectă și super rapidă)
            "model": "gpt-5-mini",
            "response_format": ["type": "json_object"],
            // Aici trimitem array-ul complet de mesaje creat mai sus
            "messages": content
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }

            if !(200...299).contains(httpResponse.statusCode) {
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let errorObj = errorJson["error"] as? [String: Any],
                    let message = errorObj["message"] as? String {
                    throw AIServiceError.unknown("OpenAI API: \(message)")
                } else {
                    let fallbackString = String(data: data, encoding: .utf8) ?? ""
                    throw AIServiceError.unknown("Eroare HTTP \(httpResponse.statusCode): \(fallbackString)")
                }
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choices = json["choices"] as? [[String: Any]], let firstChoice = choices.first,
                let message = firstChoice["message"] as? [String: Any], let contentString = message["content"] as? String else {
                throw AIServiceError.parsingFailed
            }

            // -------------------------------------------------
            // 👇 ADAUGĂ ACEST PRINT PENTRU DEBUGGING 👇
            print("========================================")
            print("🤖 RAW AI RESPONSE:")
            print(contentString)
            print("========================================")
            // -------------------------------------------------


            var cleanJSON = contentString.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanJSON.hasPrefix("```json") { cleanJSON = cleanJSON.replacingOccurrences(of: "```json", with: "") }
            if cleanJSON.hasPrefix("```") { cleanJSON = String(cleanJSON.dropFirst(3)) }
            if cleanJSON.hasSuffix("```") { cleanJSON = String(cleanJSON.dropLast(3)) }
            cleanJSON = cleanJSON.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let contentData = cleanJSON.data(using: .utf8) else { throw AIServiceError.parsingFailed }

            do {
                let aiResponse = try JSONDecoder().decode(AIGenerationResponseDTO.self, from: contentData)
                if let cards = aiResponse.flashcards {
                    return cards.map { AIFlashcard(id: UUID(), question: $0.question, answer: $0.answer) }
                } else {
                    let snippet = String(cleanJSON.prefix(120))
                    throw AIServiceError.unknown("AI a deviat de la format: \(snippet)...")
                }
            } catch {
                let snippet = String(cleanJSON.prefix(150))
                print("JSON Decode Error: \(error)\nRaw Response: \(cleanJSON)")
                throw AIServiceError.unknown("AI Output Invalid: \(snippet)...")
            }

        } catch let error as AIServiceError {
            throw error
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw AIServiceError.timeout
        } catch {
            throw AIServiceError.parsingFailed
        }
    }

    private func calculateCardsForBatch(totalRequested: Int, totalBatches: Int, currentBatchIndex: Int) -> Int {
        if totalBatches == 0 { return totalRequested }
        let base = totalRequested / totalBatches
        let remainder = totalRequested % totalBatches
        return currentBatchIndex < remainder ? base + 1 : base
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

/*
 var prompt = """
 You are an expert educational tutor creating study materials for "Active Recall".

 CRITICAL RULES:
 1. Read the provided document carefully. Identify the core concepts, events, formulas, code snippets, or definitions.
 2. Generate EXACTLY \(requestedCards) flashcards.
 3. LANGUAGE MATCHING: You MUST use the EXACT SAME LANGUAGE as the main text provided.
 4. CONTEXT COMPLETION: If the text is fragmented, use your expert knowledge to fill in the gaps so the flashcard makes complete sense factually.
 
 5. CONCISE & PRECISE ANSWERS (CRITICAL): Answers MUST be direct, strictly to the point, and highly accurate. ABSOLUTELY NO FLUFF, no filler words, and no unnecessarily long explanations. If a short answer is sufficient, keep it short. Give the exact information needed, nothing more.
 
 6. QUESTION FORMAT: The "question" MUST be a direct interrogative sentence ending with a question mark (?), or a clear "Define/Explain: X" prompt. Do NOT split sentences in half.
 
 7. MATH/LATEX: You MUST use LaTeX for math formulas, equations, or scientific symbols.
    - Use single `$` for inline math (e.g., the variable $x$ or $\\varepsilon$).
    - Use double `$$` for block math.
    - ABSOLUTELY DO NOT wrap regular text, sentences, or paragraphs in `$`.
    - WRONG: $The capital of France is Paris.$
    - CORRECT: The capital of France is Paris.
    
 8. OUTPUT FORMAT: Output MUST be a strict JSON object with a single root key "flashcards", containing an array of {"question": "...", "answer": "..."}.

 BAD EXAMPLE (Too much fluff / Unnecessary elaboration):
 {"question": "What is the capital of France?", "answer": "The capital of France is Paris. Paris is a very beautiful city known for the Eiffel Tower and it has been the capital for a very long time."}

 GOOD EXAMPLE 1 (Concise & Precise Math):
 {"question": "How is the Kleene star $L^*$ defined?", "answer": "The Kleene star $L^*$ is the union of all powers of a language $L$: $$L^* = \\bigcup_{n\\ge 0} L^n$$."}

 GOOD EXAMPLE 2 (Concise History):
 {"question": "What were the primary causes of the Daco-Roman wars (101-106 AD)?", "answer": "The Roman Empire needed to secure its borders against Dacian raids, and Emperor Trajan wanted to control Dacia's rich gold mines."}
 """

 if isOCR {
     prompt += "\n\n9. OCR CORRECTION: The provided text is extracted via OCR and may contain typos or garbled characters. Infer the correct meaning and output grammatically correct text."
 }

 return prompt
}
 */
