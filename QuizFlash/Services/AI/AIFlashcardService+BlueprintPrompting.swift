import Foundation

extension AIFlashcardService {
    nonisolated func buildBlueprintDirectMessages(
        sourceJSON: String,
        allocationJSON: String,
        targetCards: Int,
        options: AIGenerationOptions,
        sourceFingerprint: String,
        promptVersion: String
    ) throws -> [[String: Any]] {
        var values = blueprintValues(
            targetCards: targetCards,
            options: options,
            allocationJSON: allocationJSON,
            sourceFingerprint: sourceFingerprint,
            promptVersion: promptVersion
        )
        values["sourceJSON"] = sourceJSON
        return try blueprintMessages(
            instructionKey: AIPromptTemplateKey.blueprintDirect,
            userInstructionsJSON: try userInstructionsJSON(for: options),
            values: values
        )
    }

    nonisolated func buildBlueprintMapMessages(
        sourceJSON: String,
        mapIndex: Int,
        mapCount: Int,
        options: AIGenerationOptions
    ) throws -> [[String: Any]] {
        return try blueprintMessages(
            instructionKey: AIPromptTemplateKey.blueprintMap,
            includesFinalSchema: false,
            values: [
                "sourceJSON": sourceJSON,
                "mapIndex": String(mapIndex),
                "mapCount": String(mapCount),
                "cardType": options.cardType.rawValue,
                "cardLevel": options.cardLevel.rawValue
            ]
        )
    }

    nonisolated func buildBlueprintReduceMessages(
        digestJSON: String,
        allocationJSON: String,
        targetCards: Int,
        options: AIGenerationOptions,
        sourceFingerprint: String,
        promptVersion: String,
        reduceLevel: Int,
        isFinal: Bool,
        groupIndex: Int,
        groupCount: Int
    ) throws -> [[String: Any]] {
        var values = blueprintValues(
            targetCards: targetCards,
            options: options,
            allocationJSON: allocationJSON,
            sourceFingerprint: sourceFingerprint,
            promptVersion: promptVersion
        )
        values["digestJSON"] = digestJSON
        values["reduceLevel"] = String(reduceLevel)
        values["isFinal"] = isFinal ? "true" : "false"
        values["groupIndex"] = String(groupIndex)
        values["groupCount"] = String(groupCount)
        let instructionsJSON = isFinal ? try userInstructionsJSON(for: options) : nil
        return try blueprintMessages(
            instructionKey: AIPromptTemplateKey.blueprintReduce,
            includesFinalSchema: isFinal,
            userInstructionsJSON: instructionsJSON,
            values: values
        )
    }

    nonisolated func buildBlueprintRepairMessages(
        invalidBlueprintJSON: String,
        issuesJSON: String,
        sourceJSON: String,
        allocationJSON: String,
        targetCards: Int,
        options: AIGenerationOptions,
        sourceFingerprint: String,
        promptVersion: String
    ) throws -> [[String: Any]] {
        var values = blueprintValues(
            targetCards: targetCards,
            options: options,
            allocationJSON: allocationJSON,
            sourceFingerprint: sourceFingerprint,
            promptVersion: promptVersion
        )
        values["invalidBlueprintJSON"] = invalidBlueprintJSON
        values["issuesJSON"] = issuesJSON
        values["sourceJSON"] = sourceJSON
        return try blueprintMessages(
            instructionKey: AIPromptTemplateKey.blueprintRepair,
            userInstructionsJSON: try userInstructionsJSON(for: options),
            values: values
        )
    }

    nonisolated func renderBlueprintBatchContext(
        _ context: AIBlueprintBatchContext,
        coveredPrompts: [String]
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let themeJSON = String(decoding: try encoder.encode(context.theme), as: UTF8.self)
        let objectivesJSON = String(decoding: try encoder.encode(context.objectives), as: UTF8.self)
        let coveredJSON = String(decoding: try encoder.encode(coveredPrompts), as: UTF8.self)
        return try renderPromptTemplate(
            AIPromptTemplateKey.blueprintBatchContext,
            values: [
                "globalOutline": context.globalOutline,
                "themeJSON": themeJSON,
                "objectivesJSON": objectivesJSON,
                "coveredJSON": coveredJSON
            ]
        )
    }

    private nonisolated func blueprintMessages(
        instructionKey: String,
        includesFinalSchema: Bool = true,
        userInstructionsJSON: String? = nil,
        values: [String: String]
    ) throws -> [[String: Any]] {
        var system = try renderPromptTemplate(AIPromptTemplateKey.blueprintSystem)
        if includesFinalSchema {
            system += "\n" + (try renderPromptTemplate(AIPromptTemplateKey.blueprintSchema))
        }
        if userInstructionsJSON != nil {
            system += try renderPromptTemplate(AIPromptTemplateKey.systemUserInstructions)
        }

        var user = try renderPromptTemplate(instructionKey, values: values)
        if let userInstructionsJSON {
            user += try renderPromptTemplate(
                AIPromptTemplateKey.userInstructions,
                values: ["userInstructionsJSON": userInstructionsJSON]
            )
        }
        return [
            ["role": "system", "content": system],
            ["role": "user", "content": user]
        ]
    }

    private nonisolated func blueprintValues(
        targetCards: Int,
        options: AIGenerationOptions,
        allocationJSON: String,
        sourceFingerprint: String,
        promptVersion: String
    ) -> [String: String] {
        [
            "schemaVersion": String(AIBlueprintValidator.supportedSchemaVersion),
            "promptVersion": promptVersion,
            "sourceFingerprint": sourceFingerprint,
            "targetCards": String(targetCards),
            "cardType": options.cardType.rawValue,
            "cardLevel": options.cardLevel.rawValue,
            "allocationJSON": allocationJSON
        ]
    }
}
