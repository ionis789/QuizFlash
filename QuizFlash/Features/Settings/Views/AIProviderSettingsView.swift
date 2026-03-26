//
//  AIProviderSettingsView.swift
//  QuizFlash
//
//  Settings surface for saving, switching, and editing AI provider profiles.
//

import SwiftUI

// MARK: - AI Provider Settings View

struct AIProviderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AIProviderStore.self) private var aiProviderStore
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.huge) {
                activeProfileSection
                savedProfilesSection
                syntaxSection
            }
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.top, UIConstants.Spacing.large)
            .padding(.bottom, UIConstants.Spacing.huge)
        }
        .background(themeManager.groupedScreenBackground)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .safeAreaInset(edge: .top) {
            navigationBar
                .padding(.horizontal, UIConstants.Spacing.large)
                .padding(.top, UIConstants.Spacing.standard)
                .padding(.bottom, UIConstants.Spacing.small)
                .background(themeManager.groupedScreenBackground)
        }
    }

    private var navigationBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            Text("Developer AI")
                .font(.headline.weight(.bold))

            Spacer()

            NavigationLink {
                AIProviderEditorView(initialProfile: .preset(.custom), isNewProfile: true)
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
    }

    private var activeProfileSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text("Active Configuration")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if let activeProfile = aiProviderStore.activeProfile {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                    HStack(alignment: .top, spacing: UIConstants.Spacing.standard) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 52, height: 52)

                            Image(systemName: "sparkles.rectangle.stack.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(activeProfile.trimmedName)
                                .font(.headline.weight(.semibold))

                            Text(activeProfile.endpointDisplayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text("Developer-only OpenAI-compatible profile")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.tertiary)
                        }

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: UIConstants.Spacing.small) {
                        profilePill(
                            title: "Text",
                            value: activeProfile.trimmedTextModel,
                            icon: "text.alignleft"
                        )
                        profilePill(
                            title: "Vision",
                            value: activeProfile.trimmedVisionModel,
                            icon: "photo"
                        )
                    }

                    HStack(spacing: UIConstants.Spacing.small) {
                        profilePill(
                            title: "Key",
                            value: activeProfile.maskedAPIKey,
                            icon: "key.fill"
                        )

                        if activeProfile.httpRefererURL != nil || !activeProfile.trimmedXTitle.isEmpty || !activeProfile.trimmedExtraBodyJSONString.isEmpty {
                            profilePill(
                                title: "Transport",
                                value: "Custom",
                                icon: "switch.2"
                            )
                        }

                        if let validationMessage = activeProfile.generationValidationMessage {
                            Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(UIConstants.Spacing.standard)
                .background(
                    RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            } else {
                Text("No AI provider profile is available yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(UIConstants.Spacing.standard)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
            }
        }
    }

    private var savedProfilesSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HStack {
                Text("Saved Configurations")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                NavigationLink {
                    AIProviderEditorView(initialProfile: .preset(.custom), isNewProfile: true)
                } label: {
                    Label("Add Config", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold))
                }
            }

            VStack(spacing: UIConstants.Spacing.medium) {
                ForEach(aiProviderStore.profiles) { profile in
                    AIProviderRowView(
                        profile: profile,
                        isActive: aiProviderStore.activeProfile?.id == profile.id,
                        onUse: {
                            aiProviderStore.setActiveProfile(id: profile.id)
                        }
                    )
                }
            }
        }
    }

    private var syntaxSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text("Universal OpenAI-Compatible Setup")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                if let activeProfile = aiProviderStore.activeProfile {
                    Text(activeProfile.requestStyle.title)
                        .font(.headline.weight(.semibold))

                    Text(activeProfile.requestStyle.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    ForEach(AIProviderRequestStyle.openAICompatible.syntaxLines, id: \.self) { line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(UIConstants.Spacing.standard)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                )

                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    Text("Template examples")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    syntaxExampleRow(
                        provider: "DeepSeek",
                        endpoint: "api.deepseek.com/chat/completions",
                        textModel: "deepseek-chat",
                        visionModel: "deepseek-chat"
                    )

                    syntaxExampleRow(
                        provider: "OpenAI",
                        endpoint: "api.openai.com/v1",
                        textModel: "gpt-4.1-mini",
                        visionModel: "gpt-4.1-mini"
                    )

                    syntaxExampleRow(
                        provider: "OpenRouter / Grok Fast",
                        endpoint: "openrouter.ai/api/v1",
                        textModel: "x-ai/grok-4.1-fast",
                        visionModel: "x-ai/grok-4.1-fast"
                    )

                    syntaxExampleRow(
                        provider: "xAI / Grok",
                        endpoint: "api.x.ai/v1",
                        textModel: "grok-4",
                        visionModel: "grok-4"
                    )

                    Text("Base URLs are accepted. QuizFlash automatically resolves the final /chat/completions path. Optional HTTP-Referer, X-Title, and extra body JSON are merged into the request.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(UIConstants.Spacing.standard)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
    }

    private func profilePill(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text("\(title): \(value)")
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func syntaxExampleRow(
        provider: String,
        endpoint: String,
        textModel: String,
        visionModel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(provider)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text("Endpoint: \(endpoint)")
            Text("Text: \(textModel)")
            Text("Vision: \(visionModel)")
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

// MARK: - AI Provider Row

private struct AIProviderRowView: View {
    let profile: AIProviderProfile
    let isActive: Bool
    let onUse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            HStack(alignment: .top, spacing: UIConstants.Spacing.standard) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.trimmedName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(profile.endpointDisplayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if isActive {
                    Text("Active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Text: \(profile.trimmedTextModel)")
                Text("Vision: \(profile.trimmedVisionModel)")
            Text("Token: \(profile.maskedAPIKey)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: UIConstants.Spacing.small) {
                Button(action: onUse) {
                    Text(isActive ? "In Use" : "Use This")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                                .fill(isActive ? Color.accentColor.opacity(0.16) : Color.accentColor)
                        )
                        .foregroundStyle(isActive ? Color.accentColor : .white)
                }
                .buttonStyle(.plain)
                .disabled(isActive)

                NavigationLink {
                    AIProviderEditorView(initialProfile: profile, isNewProfile: false)
                } label: {
                    Text("Edit")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemFill))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(UIConstants.Spacing.standard)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

// MARK: - AI Provider Editor

struct AIProviderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AIProviderStore.self) private var aiProviderStore

    @State private var draft: AIProviderProfile
    @State private var makesProfileActive: Bool
    @State private var revealsAPIKey = false

    private let isNewProfile: Bool

    init(initialProfile: AIProviderProfile, isNewProfile: Bool) {
        _draft = State(initialValue: initialProfile)
        _makesProfileActive = State(initialValue: isNewProfile)
        self.isNewProfile = isNewProfile
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.huge) {
                identitySection
                endpointSection
                securitySection
                transportSection
                syntaxSection

                if !isNewProfile {
                    deleteSection
                }
            }
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.top, UIConstants.Spacing.large)
            .padding(.bottom, UIConstants.Spacing.huge)
        }
        .background(themeManager.groupedScreenBackground)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .safeAreaInset(edge: .top) {
            navigationBar
                .padding(.horizontal, UIConstants.Spacing.large)
                .padding(.top, UIConstants.Spacing.standard)
                .padding(.bottom, UIConstants.Spacing.small)
                .background(themeManager.groupedScreenBackground)
        }
    }

    private var navigationBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            Text(isNewProfile ? "New AI Config" : "Edit AI Config")
                .font(.headline.weight(.bold))

            Spacer()

            Button(action: saveProfile) {
                Text("Save")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(canSave ? Color.accentColor : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .disabled(!canSave)
        }
    }

    private var canSave: Bool {
        draft.editorValidationMessage == nil
    }

    private var identitySection: some View {
        settingsCard(title: "Configuration") {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                TextField("Configuration name", text: $draft.name)
                    .textInputAutocapitalization(.words)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )

                Menu {
                    ForEach(AIProviderPreset.allCases) { preset in
                        Button {
                            draft.applyPreset(preset)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(preset.title)
                                Text(preset.subtitle)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Label("Apply Template", systemImage: "wand.and.stars")
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )
                }
                .buttonStyle(.plain)

                Toggle("Make active after save", isOn: $makesProfileActive)
                    .toggleStyle(.switch)

                Text("Templates only prefill endpoint and model strings. You can freely edit everything after that, while keeping the current API key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var endpointSection: some View {
        settingsCard(title: "Endpoint & Models") {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                fieldLabel("Base URL or Chat Completions Endpoint")
                TextField("https://api.example.com/v1", text: $draft.endpointURLString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )

                Text("You can enter either a base URL like https://openrouter.ai/api/v1 or a full endpoint like https://api.x.ai/v1/chat/completions. QuizFlash resolves the final chat completions path automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                fieldLabel("Text Model")
                TextField("Model used for text and title generation", text: $draft.textModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )

                fieldLabel("Vision Model")
                TextField("Model used for image and PDF vision requests", text: $draft.visionModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )
            }
        }
    }

    private var securitySection: some View {
        settingsCard(title: "Authentication") {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                HStack {
                    fieldLabel("Bearer Token / API Key")
                    Spacer()
                    Button(revealsAPIKey ? "Hide" : "Show") {
                        revealsAPIKey.toggle()
                    }
                    .font(.caption.weight(.semibold))
                }

                Group {
                    if revealsAPIKey {
                        TextField("sk-...", text: $draft.apiKey)
                    } else {
                        SecureField("sk-...", text: $draft.apiKey)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                )

                Text("Configurations are stored in the app sandbox Application Support folder, outside source control.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var transportSection: some View {
        settingsCard(title: "Optional Headers & Extra Body") {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                fieldLabel("HTTP-Referer")
                TextField("https://your-site.example", text: $draft.httpReferer)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )

                fieldLabel("X-Title")
                TextField("QuizFlash Dev", text: $draft.xTitle)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )

                fieldLabel("Extra Body JSON")
                TextEditor(text: $draft.extraBodyJSONString)
                    .font(.system(.footnote, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )

                Text("Optional. Use this for provider-specific body fields such as OpenRouter reasoning. Example: {\"reasoning\":{\"enabled\":true}}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var syntaxSection: some View {
        settingsCard(title: "Wire Format") {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                Text(draft.requestStyle.title)
                    .font(.subheadline.weight(.semibold))

                Text(draft.requestStyle.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    ForEach(draft.requestStyle.syntaxLines, id: \.self) { line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(UIConstants.Spacing.standard)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                )

                if let validationMessage = draft.generationValidationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var deleteSection: some View {
        settingsCard(title: "Danger Zone") {
            Button(role: .destructive) {
                aiProviderStore.deleteProfile(id: draft.id)
                dismiss()
            } label: {
                HStack {
                    Spacer()
                    Label("Delete Configuration", systemImage: "trash")
                    Spacer()
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .disabled(aiProviderStore.profiles.count <= 1)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func settingsCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            content()
        }
        .padding(UIConstants.Spacing.standard)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func saveProfile() {
        guard canSave else { return }
        aiProviderStore.upsertProfile(draft, makeActive: makesProfileActive)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        AIProviderSettingsView()
            .environment(AIProviderStore.shared)
    }
}
