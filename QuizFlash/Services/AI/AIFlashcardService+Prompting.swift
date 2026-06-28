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
    ) throws -> [[String: Any]] {
        let preparedText = try preparedSourceTextForPrompt(
            text,
            cardType: options.cardType,
            needsOCRCorrection: needsOCRCorrection,
            targetCards: targetCards
        )
        return [
            ["role": "system", "content": try systemPrompt(targetCards: targetCards, isOCR: needsOCRCorrection, options: options)],
            ["role": "user", "content": try buildTextUserMessage(
                text: preparedText,
                targetCards: targetCards,
                options: options,
                cardType: options.cardType,
                sourceLabel: sourceLabel,
                batchIndex: batchIndex,
                totalBatches: totalBatches,
                passIndex: passIndex,
                coveredPrompts: coveredPrompts
            )],
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
    ) throws -> [[String: Any]] {
        var userContent: [[String: Any]] = []
        for image in images {
            guard let data = image.jpegData(compressionQuality: 0.7) else { continue }
            userContent.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())", "detail": "auto"],
            ])
        }
        userContent.append([
            "type": "text", "text": try buildVisionUserMessage(
                targetCards: targetCards,
                options: options,
                cardType: options.cardType,
                sourceLabel: sourceLabel,
                batchIndex: batchIndex,
                totalBatches: totalBatches,
                passIndex: passIndex,
                coveredPrompts: coveredPrompts
            )
        ])
        return [
            ["role": "system", "content": try systemPrompt(targetCards: targetCards, isOCR: false, options: options)],
            ["role": "user", "content": userContent],
        ]
    }

    nonisolated func buildDeckTitleMessages(fromText text: String) throws -> [[String: Any]] {
        [
            ["role": "system", "content": try renderPromptTemplate(AIPromptTemplateKey.titleSystem)],
            ["role": "user", "content": try renderPromptTemplate(
                AIPromptTemplateKey.titleUser,
                values: ["text": String(text.prefix(6_000))]
            )],
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
    ) throws -> String {
        var message = try renderPromptTemplate(
            AIPromptTemplateKey.userTextSource,
            values: ["text": text]
        )
        message += try renderPromptTemplate(
            AIPromptTemplateKey.userTextBase,
            values: [
                "batchIndex": String(batchIndex),
                "totalBatches": String(totalBatches),
                "sourceLabel": sourceLabel,
                "targetCards": String(targetCards),
                "cardTypeTitle": cardType.title
            ]
        )

        if let languageHint = options.sourceLanguageHint {
            message += try renderLanguageTemplate(AIPromptTemplateKey.userTextLanguage, languageHint: languageHint)
        }

        if passIndex > 1 {
            message += try renderPromptTemplate(AIPromptTemplateKey.userTextRepeat)
        }

        switch cardType {
        case .flashcards:
            message += try renderPromptTemplate(AIPromptTemplateKey.userTextFlashcard)
        case .quiz:
            message += try renderPromptTemplate(AIPromptTemplateKey.userTextQuiz)
        }

        if !coveredPrompts.isEmpty {
            message += try renderPromptTemplate(AIPromptTemplateKey.userTextCoveredHeader)
            for covered in coveredPrompts.prefix(4) {
                message += try renderPromptTemplate(
                    AIPromptTemplateKey.userTextCoveredItem,
                    values: ["coveredPrompt": covered]
                )
            }
        }

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
    ) throws -> String {
        var message = try renderPromptTemplate(
            AIPromptTemplateKey.userVisionBase,
            values: [
                "targetCards": String(targetCards),
                "cardTypeTitle": cardType.title,
                "batchIndex": String(batchIndex),
                "totalBatches": String(totalBatches),
                "sourceLabel": sourceLabel
            ]
        )

        if let languageHint = options.sourceLanguageHint {
            message += try renderLanguageTemplate(AIPromptTemplateKey.userVisionLanguage, languageHint: languageHint)
        }

        if passIndex > 1 {
            message += try renderPromptTemplate(AIPromptTemplateKey.userVisionRepeat)
        }

        switch cardType {
        case .flashcards:
            message += try renderPromptTemplate(AIPromptTemplateKey.userVisionFlashcard)
        case .quiz:
            message += try renderPromptTemplate(AIPromptTemplateKey.userVisionQuiz)
        }

        if !coveredPrompts.isEmpty {
            message += try renderPromptTemplate(AIPromptTemplateKey.userVisionCoveredHeader)
            for covered in coveredPrompts.prefix(4) {
                message += try renderPromptTemplate(
                    AIPromptTemplateKey.userVisionCoveredItem,
                    values: ["coveredPrompt": covered]
                )
            }
        }

        return message
    }

    nonisolated func systemPrompt(
        targetCards: Int,
        isOCR: Bool,
        options: AIGenerationOptions
    ) throws -> String {
        let outputContract = options.cardType.outputContract
        var prompt = try renderPromptTemplate(
            AIPromptTemplateKey.systemBase,
            values: [
                "targetCards": String(targetCards),
                "cardTypeTitle": options.cardType.title,
                "languageRule": try languageRulePrompt(for: options)
            ]
        )

        prompt += try requiredJSONSchemaPrompt(for: outputContract)
        prompt += try formattingRulesPrompt(for: outputContract)
        prompt += try mobileCardLayoutPrompt(for: outputContract)

        if isOCR {
            prompt += try renderPromptTemplate(AIPromptTemplateKey.systemOCR)
        }

        prompt += try cardTypePromptAddition(for: options.cardType)
        prompt += try cardLevelPromptAddition(for: options.cardLevel)
        return prompt
    }

    nonisolated func requiredJSONSchemaPrompt(for contract: AIGeneratedCardContract) throws -> String {
        switch contract {
        case .flashcard:
            return try renderPromptTemplate(AIPromptTemplateKey.schemaFlashcard)
        case .quiz:
            return try renderPromptTemplate(AIPromptTemplateKey.schemaQuiz)
        }
    }

    nonisolated func formattingRulesPrompt(for contract: AIGeneratedCardContract) throws -> String {
        switch contract {
        case .flashcard:
            return try renderPromptTemplate(AIPromptTemplateKey.rulesFlashcard)
        case .quiz:
            return try renderPromptTemplate(AIPromptTemplateKey.rulesQuiz)
        }
    }

    nonisolated func mobileCardLayoutPrompt(for contract: AIGeneratedCardContract) throws -> String {
        switch contract {
        case .flashcard:
            return try renderPromptTemplate(AIPromptTemplateKey.layoutFlashcard)
        case .quiz:
            return try renderPromptTemplate(AIPromptTemplateKey.layoutQuiz)
        }
    }

    nonisolated func preparedSourceTextForPrompt(
        _ text: String,
        cardType: AICardGenerationType,
        needsOCRCorrection: Bool,
        targetCards: Int
    ) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharsPerChunk else { return trimmed }

        let prefixLimit = maxCharsPerChunk / 2
        let suffixLimit = maxCharsPerChunk - prefixLimit
        return try renderPromptTemplate(
            AIPromptTemplateKey.sourceTruncated,
            values: [
                "prefix": String(trimmed.prefix(prefixLimit)),
                "suffix": String(trimmed.suffix(suffixLimit))
            ]
        )
    }

    nonisolated func languageRulePrompt(for options: AIGenerationOptions) throws -> String {
        if let languageHint = options.sourceLanguageHint {
            return try renderLanguageTemplate(AIPromptTemplateKey.languageLocked, languageHint: languageHint)
        }

        return try renderPromptTemplate(AIPromptTemplateKey.languageAuto)
    }

    nonisolated func cardTypePromptAddition(for type: AICardGenerationType) throws -> String {
        switch type {
        case .flashcards:
            return try renderPromptTemplate(AIPromptTemplateKey.cardTypeFlashcard)
        case .quiz:
            return try renderPromptTemplate(AIPromptTemplateKey.cardTypeQuiz)
        }
    }

    nonisolated func cardLevelPromptAddition(for level: AICardGenerationLevel) throws -> String {
        switch level {
        case .simple:
            return try renderPromptTemplate(AIPromptTemplateKey.depthSimple)
        case .pro:
            return try renderPromptTemplate(AIPromptTemplateKey.depthPro)
        }
    }

    nonisolated private func renderLanguageTemplate(
        _ key: String,
        languageHint: AIGenerationLanguageHint
    ) throws -> String {
        try renderPromptTemplate(
            key,
            values: [
                "languageDisplayName": languageHint.displayName,
                "languageCode": languageHint.languageCode
            ]
        )
    }

    nonisolated private func renderPromptTemplate(
        _ key: String,
        values: [String: String] = [:]
    ) throws -> String {
        guard let promptBundle else {
            throw AIServiceError.unknown("AI prompt configuration is unavailable.")
        }

        var rendered = try promptBundle.template(key)
        for (placeholder, value) in values {
            rendered = rendered.replacingOccurrences(of: "{{\(placeholder)}}", with: value)
        }

        guard rendered.range(of: #"\{\{[^}]+\}\}"#, options: .regularExpression) == nil else {
            throw AIServiceError.unknown("AI prompt configuration has unresolved placeholders.")
        }

        return rendered
    }
}
