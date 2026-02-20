//
//  AIFlashcardService.swift
//  QuizFlash
//

import Foundation
import UIKit

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
        case .invalidAPIKey: return "AI API key is not configured or invalid."
        case .networkError: return "Network error. Please check your internet connection."
        case .invalidResponse: return "Received an invalid response from the AI service."
        case .parsingFailed: return "Failed to parse AI response. Please try again."
        case .rateLimitExceeded: return "Too many requests. Please wait a moment and try again."
        case .timeout: return "The request timed out because the document is too large. Try fewer pages."
        case .unknown(let message): return "OpenAI Error: \(message)"
        }
    }
}

private struct AIGenerationResponseDTO: Codable {
    struct CardDTO: Codable {
        let question: String
        let answer: String
    }
    let flashcards: [CardDTO]
}

@MainActor
public final class AIFlashcardService {
    // ⚠️ Atenție: Cheia ar trebui ascunsă în producție (ex. .env / Keychain)
    private let apiKey = "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"
    
    
    private let apiEndpoint = "https://api.openai.com/v1/chat/completions"
    
    private let session: URLSession
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }
    
    func generateFlashcards(from images: [UIImage], targetCards: Int, onProgress: @escaping (Double, Int) -> Void) async throws -> [AIFlashcard] {
        let batchSize = 8
        let batches = images.chunked(into: batchSize)
        var allFlashcards: [AIFlashcard] = []
        
        for (index, batch) in batches.enumerated() {
            let cardsForThisBatch = calculateCardsForBatch(totalRequested: targetCards, totalBatches: batches.count, currentBatchIndex: index)
            
            if cardsForThisBatch > 0 {
                let messageContent = buildMultimodalContent(from: batch, requestedCards: cardsForThisBatch)
                let flashcardsFromBatch = try await sendVisionRequest(content: messageContent)
                allFlashcards.append(contentsOf: flashcardsFromBatch)
            }
            
            let progress = Double(index + 1) / Double(batches.count)
            onProgress(progress, allFlashcards.count)
        }
        
        return allFlashcards
    }
    
    private func buildMultimodalContent(from images: [UIImage], requestedCards: Int) -> [[String: Any]] {
        // PROMPT UNIVERSAL, LIMBAJ AGNOSTIC, AXAT PE CALITATE MAXIMĂ
        let promptText = """
        You are an expert educational tutor creating study materials for "Active Recall" across various subjects (History, Literature, Mathematics, Computer Science, Biology, etc.).
        
        CRITICAL RULES:
        1. Read the provided document pages carefully. Identify the core concepts, events, formulas, code snippets, or definitions.
        2. Generate EXACTLY \(requestedCards) flashcards.
        3. LANGUAGE MATCHING: You MUST use the EXACT SAME LANGUAGE as the main text in the images (e.g., if the text is in Spanish, output in Spanish; if English, output in English; if Romanian, output in Romanian).
        4. CONTEXT COMPLETION: If the text is fragmented, lacks context, or contains partial formulas/sentences, you MUST use your expert knowledge to fill in the gaps. Every flashcard must make complete sense on its own and be factually correct, regardless of how limited the source image is.
        5. ELABORATE & EXPLAIN: Do not give overly brief answers. The "answer" must be detailed, well-explained, and clearly structured so the student truly understands the concept. For math/code, define the variables and explain their purpose.
        6. QUESTION FORMAT: The "question" MUST be a direct, clear interrogative sentence ending with a question mark (?), or a clear "Define/Explain: X" prompt. Do NOT just split a sentence in half.
        7. MATH/LATEX: For ANY math formulas, equations, or scientific symbols, you MUST use LaTeX formatting wrapped in single `$` for inline math, and double `$$` for block math.
        8. OUTPUT FORMAT: Output MUST be a strict JSON object with a single root key "flashcards", containing an array of {"question": "...", "answer": "..."}.

        BAD EXAMPLE (Too brief, lacks context, poor question):
        {"question": "What is L*?", "answer": "It is the union of L^n."}
        
        GOOD EXAMPLE 1 (Math / Computer Science):
        {"question": "How is the Kleene star (iteration) $L^*$ defined in formal language theory, and what does it represent?", "answer": "The Kleene star $L^*$ of a language $L$ is defined as the union of all its powers: $$L^* = \\bigcup_{n\\ge 0} L^n$$. It represents the set of all strings that can be formed by concatenating zero or more strings from the base language $L$. Note: $L^0 = \\{\\varepsilon\\}$ contains only the empty string."}
        
        GOOD EXAMPLE 2 (History / Humanities):
        {"question": "What were the primary causes and outcomes of the Daco-Roman wars (101-106 AD)?", "answer": "The Daco-Roman wars, fought between the Roman Empire (led by Emperor Trajan) and the Dacian Kingdom (led by King Decebalus), were primarily caused by the Roman need to secure their borders and gain control over Dacia's rich gold mines. The outcome was the decisive defeat of Dacia, the suicide of Decebalus, and the transformation of Dacia into a Roman province, which significantly influenced the formation of the Romanian people."}
        """
        
        var contentArray: [[String: Any]] = [
            ["type": "text", "text": promptText]
        ]
        
        for image in images {
            if let jpegData = image.jpegData(compressionQuality: 0.6) {
                let base64String = jpegData.base64EncodedString()
                let imagePayload: [String: Any] = [
                    "type": "image_url",
                    "image_url": [
                        "url": "data:image/jpeg;base64,\(base64String)",
                        "detail": "high"
                    ]
                ]
                contentArray.append(imagePayload)
            }
        }
        return contentArray
    }
    
    private func sendVisionRequest(content: [[String: Any]]) async throws -> [AIFlashcard] {
        var request = URLRequest(url: URL(string: apiEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "gpt-5-mini",
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "user", "content": content]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIServiceError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let errorString = String(data: data, encoding: .utf8) ?? "Unknown Error"
                if httpResponse.statusCode == 401 { throw AIServiceError.invalidAPIKey }
                if httpResponse.statusCode == 429 { throw AIServiceError.rateLimitExceeded }
                throw AIServiceError.unknown(errorString)
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let contentString = message["content"] as? String,
                  let contentData = contentString.data(using: .utf8) else {
                throw AIServiceError.parsingFailed
            }

            let aiResponse = try JSONDecoder().decode(AIGenerationResponseDTO.self, from: contentData)
            return aiResponse.flashcards.map { AIFlashcard(id: UUID(), question: $0.question, answer: $0.answer) }
            
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw AIServiceError.timeout
        } catch {
            print("Eroare la parsare: \(error)")
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
