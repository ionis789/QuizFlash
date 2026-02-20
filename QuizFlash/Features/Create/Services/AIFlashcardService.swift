//
//  AIFlashcardService.swift
//  QuizFlash
//

import Foundation

// MARK: - AI Service Errors
public enum AIServiceError: LocalizedError {
    case invalidAPIKey
    case networkError
    case invalidResponse
    case parsingFailed
    case rateLimitExceeded
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "AI API key is not configured or invalid."
        case .networkError:
            return "Network error. Please check your internet connection."
        case .invalidResponse:
            return "Received an invalid response from the AI service."
        case .parsingFailed:
            return "Failed to parse AI response. Please try again."
        case .rateLimitExceeded:
            return "Too many requests. Please wait a moment and try again."
        case .unknown(let message):
            return "OpenAI Error: \(message)"
        }
    }
}

// MARK: - Private DTOs for Safe Decoding
// Folosim acest DTO ca să decodăm doar ce ne dă AI-ul, evitând crăparea aplicației din cauza lipsei UUID-ului
private struct AIGenerationResponseDTO: Codable {
    struct CardDTO: Codable {
        let question: String
        let answer: String
    }
    let flashcards: [CardDTO]
}

// MARK: - AI Flashcard Service
@MainActor
public final class AIFlashcardService {

    // MARK: - Configuration
    // ⚠️ Asigură-te că ascunzi această cheie înainte de a lansa aplicația în App Store
    private let apiKey: String = "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"
    private let apiEndpoint = "https://api.openai.com/v1/chat/completions"

    public init() {}

    // MARK: - Generate Flashcards
    func generateFlashcards(from text: String) async throws -> [AIFlashcard] {
        guard !apiKey.isEmpty else {
            return generateMockFlashcards(from: text)
        }

        guard let url = URL(string: apiEndpoint) else {
            throw AIServiceError.networkError
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // System Prompt - Forțăm păstrarea limbii și formatul JSON
        let systemPrompt = """
        You are an expert educational content creator.
        
        CRITICAL RULES:
        1. You MUST generate the flashcards in the EXACT SAME LANGUAGE as the provided text (e.g., if the text is in Romanian, respond in Romanian).
        2. Output MUST be a valid JSON object.
        3. The JSON object must have a single root key named "flashcards".
        4. The value of "flashcards" must be an array of objects.
        5. Each object in the array must have exactly two keys: "question" and "answer".
        """
        
        // User Prompt - Adăugăm cuvântul "JSON" și aici pentru a satisface cerințele stricte ale API-ului
        let userPrompt = """
        Generate 5 to 15 high-quality flashcards based on the following text.
        Return the result in JSON format.
        
        Text:
        \(text)
        """
        
        let body: [String: Any] = [
            "model": "gpt-5-mini",
            "response_format": ["type": "json_object"],
            "max_completion_tokens": 2500,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Make the request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        // Error Handling
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown Error"
            print("OpenAI Error (\(httpResponse.statusCode)): \(errorString)")

            if httpResponse.statusCode == 401 { throw AIServiceError.invalidAPIKey }
            if httpResponse.statusCode == 429 { throw AIServiceError.rateLimitExceeded }

            throw AIServiceError.unknown(errorString)
        }

        // Parse response
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String,
                  let contentData = content.data(using: .utf8) else {
                throw AIServiceError.parsingFailed
            }

            // Decodăm folosind DTO-ul sigur
            let aiResponse = try JSONDecoder().decode(AIGenerationResponseDTO.self, from: contentData)
            
            // Mapăm DTO-urile către modelul real al aplicației tale și generăm UUID-ul lipsă
            let finalFlashcards = aiResponse.flashcards.map { dto in
                AIFlashcard(id: UUID(), question: dto.question, answer: dto.answer)
            }
            
            return finalFlashcards

        } catch {
            print("Parsing Error: \(error.localizedDescription)")
            if let rawString = String(data: data, encoding: .utf8) {
                print("Raw payload was: \(rawString)")
            }
            throw AIServiceError.parsingFailed
        }
    }

    // MARK: - Mock Generation (Fallback)
    private func generateMockFlashcards(from text: String) -> [AIFlashcard] {
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 20 }

        var flashcards: [AIFlashcard] = []

        for (_, paragraph) in paragraphs.prefix(3).enumerated() {
            let words = paragraph.components(separatedBy: .whitespaces)
            if words.count > 5 {
                let questionWords = words.prefix(min(5, words.count)).joined(separator: " ")
                flashcards.append(AIFlashcard(question: "Explain: \(questionWords)...?", answer: paragraph))
            }
        }

        if flashcards.isEmpty && !text.isEmpty {
            flashcards.append(AIFlashcard(question: "What is the main topic?", answer: text.prefix(200) + (text.count > 200 ? "..." : "")))
        }

        return flashcards
    }
}
