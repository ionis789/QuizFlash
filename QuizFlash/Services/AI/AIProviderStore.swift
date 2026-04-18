//
//  AIProviderStore.swift
//  QuizFlash
//
//  Stores editable AI provider profiles outside source control so the active
//  endpoint, models, and API key can be changed without touching app code.
//

import Foundation
import Observation
import OSLog

// MARK: - AI Request Style

/// The wire format QuizFlash can currently send to AI providers.
enum AIProviderRequestStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case openAICompatible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAICompatible:
            return "OpenAI-Compatible API"
        }
    }

    var summary: String {
        switch self {
        case .openAICompatible:
            return "Use any provider that mirrors OpenAI chat completions: base URL or endpoint, Bearer auth, model, messages, and optional custom headers/body."
        }
    }

    var syntaxLines: [String] {
        switch self {
        case .openAICompatible:
            return [
                "POST <base URL>/chat/completions",
                "Authorization: Bearer <API_KEY>",
                "Content-Type: application/json",
                "Optional: HTTP-Referer, X-Title",
                "JSON: model, messages, response_format, temperature, ...extra_body"
            ]
        }
    }
}

// MARK: - AI Provider Presets

/// Ready-to-use provider templates that prefill endpoint and model syntax.
enum AIProviderPreset: String, CaseIterable, Identifiable {
    case deepSeek
    case openAI
    case openRouter
    case xAI
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deepSeek:
            return "DeepSeek"
        case .openAI:
            return "OpenAI"
        case .openRouter:
            return "OpenRouter"
        case .xAI:
            return "xAI / Grok"
        case .custom:
            return "Custom Compatible"
        }
    }

    var subtitle: String {
        switch self {
        case .deepSeek:
            return "DeepSeek endpoint with deepseek-chat defaults."
        case .openAI:
            return "OpenAI endpoint with GPT-4.1 Mini defaults."
        case .openRouter:
            return "OpenRouter base URL with Grok 4.1 Fast defaults."
        case .xAI:
            return "xAI endpoint with Grok defaults over chat completions."
        case .custom:
            return "Use any custom endpoint that follows the OpenAI chat completions structure."
        }
    }
}

// MARK: - AI Provider Profile

/// One saved AI provider configuration editable from the Settings screen.
struct AIProviderProfile: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var name: String
    var requestStyle: AIProviderRequestStyle
    var endpointURLString: String
    var apiKey: String
    var textModel: String
    var visionModel: String
    var httpReferer: String
    var xTitle: String
    var extraBodyJSONString: String

    init(
        id: UUID = UUID(),
        name: String,
        requestStyle: AIProviderRequestStyle = .openAICompatible,
        endpointURLString: String,
        apiKey: String,
        textModel: String,
        visionModel: String,
        httpReferer: String = "",
        xTitle: String = "",
        extraBodyJSONString: String = ""
    ) {
        self.id = id
        self.name = name
        self.requestStyle = requestStyle
        self.endpointURLString = endpointURLString
        self.apiKey = apiKey
        self.textModel = textModel
        self.visionModel = visionModel
        self.httpReferer = httpReferer
        self.xTitle = xTitle
        self.extraBodyJSONString = extraBodyJSONString
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedEndpointURLString: String {
        endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedTextModel: String {
        textModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedVisionModel: String {
        visionModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedHTTPReferer: String {
        httpReferer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedXTitle: String {
        xTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedExtraBodyJSONString: String {
        extraBodyJSONString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var endpointURL: URL? {
        resolvedRequestURL
    }

    var baseURLOrEndpoint: URL? {
        guard let url = URL(string: trimmedEndpointURLString) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }

    var resolvedRequestURL: URL? {
        guard let url = baseURLOrEndpoint else { return nil }

        let normalizedPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath.hasSuffix("chat/completions") {
            return url
        }

        let suffix = normalizedPath.isEmpty ? "chat/completions" : "\(normalizedPath)/chat/completions"
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/" + suffix
        return components.url
    }

    var httpRefererURL: URL? {
        guard !trimmedHTTPReferer.isEmpty else { return nil }
        guard let url = URL(string: trimmedHTTPReferer) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }

    var extraBodyObject: [String: Any]? {
        guard !trimmedExtraBodyJSONString.isEmpty else { return nil }
        guard let data = trimmedExtraBodyJSONString.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    var endpointDisplayName: String {
        resolvedRequestURL?.host() ?? trimmedEndpointURLString
    }

    var maskedAPIKey: String {
        let key = trimmedAPIKey
        guard !key.isEmpty else { return "No API key" }
        let suffix = String(key.suffix(4))
        return "••••\(suffix)"
    }

    var editorValidationMessage: String? {
        if trimmedName.isEmpty {
            return "Add a provider name."
        }
        if resolvedRequestURL == nil {
            return "The AI base URL or endpoint must be a valid HTTP or HTTPS URL."
        }
        if trimmedTextModel.isEmpty {
            return "Add a text model."
        }
        if trimmedVisionModel.isEmpty {
            return "Add a vision model."
        }
        if !trimmedHTTPReferer.isEmpty && httpRefererURL == nil {
            return "HTTP-Referer must be a valid HTTP or HTTPS URL."
        }
        if !trimmedExtraBodyJSONString.isEmpty && extraBodyObject == nil {
            return "Extra body must be a valid JSON object."
        }
        return nil
    }

    var generationValidationMessage: String? {
        if let editorValidationMessage {
            return editorValidationMessage
        }
        if trimmedAPIKey.isEmpty {
            return "Add an API key in Labs > Development Settings > Developer AI."
        }
        return nil
    }

    static func preset(_ preset: AIProviderPreset) -> AIProviderProfile {
        switch preset {
        case .deepSeek:
            return AIProviderProfile(
                name: "DeepSeek",
                endpointURLString: "https://api.deepseek.com/chat/completions",
                apiKey: "",
                textModel: "deepseek-chat",
                visionModel: "deepseek-chat"
            )
        case .openAI:
            return AIProviderProfile(
                name: "OpenAI",
                endpointURLString: "https://api.openai.com/v1",
                apiKey: "",
                textModel: "gpt-4.1-mini",
                visionModel: "gpt-4.1-mini"
            )
        case .openRouter:
            return AIProviderProfile(
                name: "OpenRouter",
                endpointURLString: "https://openrouter.ai/api/v1",
                apiKey: "",
                textModel: "x-ai/grok-4.1-fast",
                visionModel: "x-ai/grok-4.1-fast",
                xTitle: "QuizFlash Dev"
            )
        case .xAI:
            return AIProviderProfile(
                name: "xAI / Grok",
                endpointURLString: "https://api.x.ai/v1",
                apiKey: "",
                textModel: "grok-4",
                visionModel: "grok-4"
            )
        case .custom:
            return AIProviderProfile(
                name: "Custom Provider",
                endpointURLString: "https://example.com/v1/chat/completions",
                apiKey: "",
                textModel: "model-name",
                visionModel: "vision-model-name"
            )
        }
    }

    mutating func applyPreset(_ preset: AIProviderPreset) {
        let currentID = id
        let preservedAPIKey = apiKey
        self = Self.preset(preset)
        id = currentID
        apiKey = preservedAPIKey
    }
}

// MARK: - AI Provider Store

/// Observable persistence layer for saved AI provider profiles and the active provider.
@Observable
@MainActor
final class AIProviderStore {
    @MainActor static let shared = AIProviderStore()

    private struct StoragePayload: Codable {
        let activeProfileID: UUID?
        let profiles: [AIProviderProfile]
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuizFlash",
        category: "AIProviderStore"
    )

    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let fileURL: URL

    private(set) var profiles: [AIProviderProfile]
    var activeProfileID: UUID?
    var showPersistenceError = false
    var persistenceErrorMessage = ""

    var activeProfile: AIProviderProfile? {
        guard let activeProfileID else { return profiles.first }
        return profiles.first(where: { $0.id == activeProfileID }) ?? profiles.first
    }

    init(
        fileURL: URL = AIProviderStore.makeStorageURL(),
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL

        if let payload = Self.loadPayload(from: fileURL, fileManager: fileManager) {
            profiles = payload.profiles.isEmpty ? Self.defaultProfiles() : payload.profiles
            activeProfileID = payload.activeProfileID ?? profiles.first?.id
        } else {
            profiles = Self.defaultProfiles()
            activeProfileID = profiles.first?.id
            persist()
        }

        sanitizeStateIfNeeded()
    }

    @discardableResult
    func setActiveProfile(id: UUID) -> Bool {
        guard profiles.contains(where: { $0.id == id }) else { return false }
        guard activeProfileID != id else { return true }
        let previousActiveProfileID = activeProfileID
        activeProfileID = id
        guard persist(fallbackMessage: "The active AI configuration couldn't be saved right now.") else {
            activeProfileID = previousActiveProfileID
            return false
        }
        return true
    }

    @discardableResult
    func upsertProfile(_ profile: AIProviderProfile, makeActive: Bool) -> Bool {
        let previousProfiles = profiles
        let previousActiveProfileID = activeProfileID

        if let existingIndex = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[existingIndex] = profile
        } else {
            profiles.append(profile)
        }

        if makeActive || activeProfileID == nil {
            activeProfileID = profile.id
        }

        sanitizeStateIfNeeded()
        guard persist(fallbackMessage: "The AI configuration couldn't be saved right now.") else {
            profiles = previousProfiles
            activeProfileID = previousActiveProfileID
            return false
        }
        return true
    }

    @discardableResult
    func deleteProfile(id: UUID) -> Bool {
        guard profiles.count > 1 else { return false }
        let previousProfiles = profiles
        let previousActiveProfileID = activeProfileID
        profiles.removeAll { $0.id == id }

        if activeProfileID == id {
            activeProfileID = profiles.first?.id
        }

        sanitizeStateIfNeeded()
        guard persist(fallbackMessage: "The AI configuration couldn't be deleted right now.") else {
            profiles = previousProfiles
            activeProfileID = previousActiveProfileID
            return false
        }
        return true
    }

    func dismissPersistenceError() {
        showPersistenceError = false
        persistenceErrorMessage = ""
    }

    private func sanitizeStateIfNeeded() {
        if profiles.isEmpty {
            profiles = Self.defaultProfiles()
        }

        if let activeProfileID, profiles.contains(where: { $0.id == activeProfileID }) {
            return
        }

        activeProfileID = profiles.first?.id
    }

    @discardableResult
    private func persist(fallbackMessage: String = "The AI configuration changes couldn't be saved right now.") -> Bool {
        let payload = StoragePayload(activeProfileID: activeProfileID, profiles: profiles)

        do {
            let directoryURL = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)

            try data.write(to: fileURL, options: [.atomic])

            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fileURL.path
            )

            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableFileURL = fileURL
            try? mutableFileURL.setResourceValues(values)
            return true
        } catch {
            logger.error("Failed to persist AI provider profiles: \(error.localizedDescription)")
            let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            persistenceErrorMessage = description.isEmpty ? fallbackMessage : description
            showPersistenceError = true
            return false
        }
    }

    private static func defaultProfiles() -> [AIProviderProfile] {
        [
            .preset(.deepSeek),
            .preset(.openAI),
            .preset(.openRouter)
        ]
    }

    nonisolated static func makeStorageURL(fileManager: FileManager = .default) -> URL {
        let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL.documentsDirectory

        return applicationSupportURL
            .appendingPathComponent("AIConfiguration", isDirectory: true)
            .appendingPathComponent("provider_profiles.json", isDirectory: false)
    }

    private static func loadPayload(
        from fileURL: URL,
        fileManager: FileManager
    ) -> StoragePayload? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            return try decoder.decode(StoragePayload.self, from: data)
        } catch {
            return nil
        }
    }
}
