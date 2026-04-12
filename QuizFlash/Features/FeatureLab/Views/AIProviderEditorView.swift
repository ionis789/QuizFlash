//
//  AIProviderEditorView.swift
//  QuizFlash
//
//  Development-only editor for creating and updating saved AI provider profiles.
//

import SwiftUI

private let kAIProviderEditorChromeSpace = "AIProviderEditorChromeSpace"

// MARK: - AI Provider Editor

struct AIProviderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AIProviderStore.self) private var aiProviderStore

    @State private var draft: AIProviderProfile
    @State private var makesProfileActive: Bool
    @State private var revealsAPIKey = false
    @State private var isCollapsedTitleVisible = false
    @State private var navigationBarHeight: CGFloat =
        UIConstants.Size.capsuleHeight + UIConstants.Layout.deckNavigationTopPadding
    @State private var navigationBarBottomY: CGFloat = 0

    private let isNewProfile: Bool

    init(initialProfile: AIProviderProfile, isNewProfile: Bool) {
        _draft = State(initialValue: initialProfile)
        _makesProfileActive = State(initialValue: isNewProfile)
        self.isNewProfile = isNewProfile
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.huge) {
                    LargeScreenTitle(title: navigationTitle)
                        .collapsibleTitleRevealAnchor(
                            in: kAIProviderEditorChromeSpace,
                            navigationBarBottomY: navigationBarBottomY,
                            revealClearance: SettingsChromeMetrics.pillRevealClearance,
                            isVisible: $isCollapsedTitleVisible
                        )

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
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: navigationBarHeight + UIConstants.Spacing.small)
            }

            navigationBar
        }
        .coordinateSpace(name: kAIProviderEditorChromeSpace)
        .background(themeManager.groupedScreenBackground)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
    }

    private var navigationBar: some View {
        CollapsibleTitleNavigationBar(
            coordinateSpaceName: kAIProviderEditorChromeSpace,
            onHeightChange: { navigationBarHeight = $0 },
            onBottomChange: { navigationBarBottomY = $0 }
        ) {
            ChromeCircleIconButton(systemName: "chevron.left") {
                dismiss()
            }
        } center: { maxWidth in
            CollapsibleTitlePill(
                title: navigationTitle,
                maxWidth: maxWidth,
                isVisible: isCollapsedTitleVisible
            )
        } trailing: {
            Button(action: saveProfile) {
                Text("Save")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(canSave ? Color.accentColor : .secondary)
                    .padding(.horizontal, UIConstants.Spacing.standard)
                    .frame(height: UIConstants.Size.actionButton)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
    }

    private var navigationTitle: String {
        isNewProfile ? "New AI Config" : "Edit AI Config"
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
