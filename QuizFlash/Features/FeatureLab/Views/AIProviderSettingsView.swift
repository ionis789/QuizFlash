//
//  AIProviderSettingsView.swift
//  QuizFlash
//
//  Development-only surface for saving, switching, and editing AI provider profiles.
//

import SwiftUI

private let kAIProviderSettingsChromeSpace = "AIProviderSettingsChromeSpace"

// MARK: - AI Provider Settings View

private struct AIProviderEditorRoute: Identifiable {
    let profile: AIProviderProfile
    let isNewProfile: Bool

    var id: UUID { profile.id }
}

struct AIProviderSettingsView: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(\.dismiss) private var dismiss
    @Environment(AIProviderStore.self) private var aiProviderStore
    @Environment(ThemeManager.self) private var themeManager
    @State private var isCollapsedTitleVisible = false
    @State private var navigationBarHeight: CGFloat =
        UIConstants.Size.capsuleHeight + UIConstants.Layout.deckNavigationTopPadding
    @State private var navigationBarBottomY: CGFloat = 0
    @State private var editorRoute: AIProviderEditorRoute?

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                themeManager.groupedScreenBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: UIConstants.Spacing.huge) {
                        LargeScreenTitle(title: "Developer AI")
                            .collapsibleTitleRevealAnchor(
                                in: kAIProviderSettingsChromeSpace,
                                navigationBarBottomY: navigationBarBottomY,
                                revealClearance: SettingsChromeMetrics.pillRevealClearance,
                                isVisible: $isCollapsedTitleVisible
                            )

                        activeProfileSection
                        savedProfilesSection
                        syntaxSection
                    }
                    .padding(.horizontal, UIConstants.Spacing.large)
                    .padding(.top, UIConstants.Spacing.large)
                    .padding(.bottom, UIConstants.Spacing.huge)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: navigationBarHeight + UIConstants.Spacing.small)
                }
            }
            .screenTopEdgeShadow(
                topHeight: structuralTopEdgeShadowHeight,
                topRevealProgress: isCollapsedTitleVisible ? 1 : 0,
                debugScreenID: "featurelab.ai-provider-settings",
                style: .progressiveBlur()
            )

            navigationBar
        }
        .coordinateSpace(name: kAIProviderSettingsChromeSpace)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .sheet(item: $editorRoute) { route in
            AIProviderEditorView(
                initialProfile: route.profile,
                isNewProfile: route.isNewProfile
            )
        }
        .alert("Save Error", isPresented: aiProviderPersistenceErrorBinding) {
            Button("OK", role: .cancel) {
                aiProviderStore.dismissPersistenceError()
            }
        } message: {
            Text(
                aiProviderStore.persistenceErrorMessage.isEmpty
                    ? "The AI configuration changes couldn't be saved right now."
                    : aiProviderStore.persistenceErrorMessage
            )
        }
    }

    private var structuralTopEdgeShadowHeight: CGFloat {
        if navigationBarBottomY > 0 {
            return navigationBarBottomY
        }
        return UIConstants.Layout.topEdgeShadowHeight
    }

    private var navigationBar: some View {
        CollapsibleTitleNavigationBar(
            coordinateSpaceName: kAIProviderSettingsChromeSpace,
            onHeightChange: { navigationBarHeight = $0 },
            onBottomChange: { navigationBarBottomY = $0 }
        ) {
            ChromeCircleIconButton(systemName: "chevron.left") {
                dismiss()
            }
        } center: { maxWidth in
            CollapsibleTitlePill(
                title: "Developer AI",
                maxWidth: maxWidth,
                isVisible: isCollapsedTitleVisible
            )
        } trailing: {
            Button {
                editorRoute = AIProviderEditorRoute(profile: .preset(.custom), isNewProfile: true)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: UIConstants.Size.actionIcon, weight: .bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary)
                    .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
            }
            .buttonStyle(.plain)
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

                        if let validationMessage = activeProfile.localizedGenerationValidationMessage(locale: appPreferences.resolvedLocale) {
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

                Button {
                    editorRoute = AIProviderEditorRoute(profile: .preset(.custom), isNewProfile: true)
                } label: {
                    Label("Add Config", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: UIConstants.Spacing.medium) {
                ForEach(aiProviderStore.profiles) { profile in
                    AIProviderRowView(
                        profile: profile,
                        isActive: aiProviderStore.activeProfile?.id == profile.id,
                        onUse: {
                            aiProviderStore.setActiveProfile(id: profile.id)
                        },
                        onEdit: {
                            editorRoute = AIProviderEditorRoute(profile: profile, isNewProfile: false)
                        }
                    )
                }
            }
        }
    }

    private var aiProviderPersistenceErrorBinding: Binding<Bool> {
        Binding(
            get: { aiProviderStore.showPersistenceError },
            set: { newValue in
                if !newValue {
                    aiProviderStore.dismissPersistenceError()
                }
            }
        )
    }

    private var syntaxSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text("Universal OpenAI-Compatible Setup")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                if let activeProfile = aiProviderStore.activeProfile {
                    Text(activeProfile.requestStyle.localizedTitle(locale: appPreferences.resolvedLocale))
                        .font(.headline.weight(.semibold))

                    Text(activeProfile.requestStyle.localizedSummary(locale: appPreferences.resolvedLocale))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    ForEach(AIProviderRequestStyle.openAICompatible.localizedSyntaxLines(locale: appPreferences.resolvedLocale), id: \.self) { line in
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
                        textModel: "deepseek-v4-flash",
                        visionModel: "deepseek-v4-flash"
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

#Preview {
    NavigationStack {
        AIProviderSettingsView()
            .environment(AIProviderStore.shared)
    }
}
