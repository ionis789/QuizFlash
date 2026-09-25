#if QUIZFLASH_DEVELOPMENT
import SwiftUI

/// Development-only home for active diagnostics and configuration tools.
struct LabsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(DevelopmentPreferences.self) private var developmentPreferences
    @Environment(OnboardingStateStore.self) private var onboardingStateStore
    @Environment(ThemeManager.self) private var themeManager

    @State private var backendTraceEventCount = 0
    @State private var aiGenerationTraceCount = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                configurationSection
                diagnosticsSection
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.top, UIConstants.Spacing.large)
            .padding(.bottom, UIConstants.Spacing.huge)
        }
        .background(themeManager.groupedScreenBackground.ignoresSafeArea())
        .navigationTitle(localized("Labs"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            navigationBar
        }
        .swipeBack { dismiss() }
        .task {
            backendTraceEventCount = await BackendTraceStore.shared.eventCount()
            aiGenerationTraceCount = await AIDebugTraceStore.shared.listRuns()
                .filter { $0.kind == .generation }
                .count
        }
    }

    private var configurationSection: some View {
        SettingsSectionCard(
            title: SettingsTextContent.verbatim(localized("Configuration")),
            subtitle: SettingsTextContent.verbatim(localized("Development-only appearance and preview tools."))
        ) {
            VStack(spacing: UIConstants.Spacing.standard) {
                NavigationLink {
                    BorderDesignSettingsView()
                } label: {
                    SettingsNavigationRow(
                        icon: "rectangle.dashed",
                        tint: themeManager.accentColor.color,
                        title: SettingsTextContent.verbatim(localized("Border")),
                        detail: SettingsTextContent.verbatim(localized("Global border style")),
                        value: appPreferences.borderDesign.preset.localizedTitle(
                            locale: appPreferences.resolvedLocale
                        )
                    )
                }
                .noPressEffectButtonStyle()

                SettingsCardDivider()

                ColorPicker(
                    selection: partialSheetBackgroundColorBinding,
                    supportsOpacity: false
                ) {
                    HStack(spacing: UIConstants.Spacing.medium) {
                        SettingsRowIcon(
                            icon: "rectangle.bottomhalf.filled",
                            tint: themeManager.accentColor.color
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(localized("Partial Sheet Background"))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(themeManager.textPrimary)

                            Text(developmentPreferences.partialSheetBackgroundHex)
                                .font(.caption.monospaced().weight(.semibold))
                                .foregroundStyle(themeManager.textSecondary)
                        }
                    }
                }

                SettingsCardDivider()

                Button {
                    onboardingStateStore.presentPreview()
                } label: {
                    SettingsNavigationRow(
                        icon: "sparkles.rectangle.stack",
                        tint: themeManager.accentColor.color,
                        title: SettingsTextContent.verbatim(localized("Preview Onboarding")),
                        detail: nil,
                        value: nil
                    )
                }
                .noPressEffectButtonStyle()
            }
        }
    }

    private var diagnosticsSection: some View {
        SettingsSectionCard(
            title: SettingsTextContent.verbatim(localized("Diagnostics")),
            subtitle: SettingsTextContent.verbatim(localized("Runtime tools available only in Development builds."))
        ) {
            VStack(spacing: UIConstants.Spacing.standard) {
                NavigationLink {
                    AIGenerationLabView()
                } label: {
                    SettingsNavigationRow(
                        icon: "bolt.horizontal.circle.fill",
                        tint: themeManager.accentColor.color,
                        title: SettingsTextContent.verbatim(localized("AI Generation Lab")),
                        detail: SettingsTextContent.verbatim(localized("Corpus and reproducible test configuration")),
                        value: nil
                    )
                }
                .noPressEffectButtonStyle()

                SettingsCardDivider()

                NavigationLink {
                    BackendTraceView()
                } label: {
                    SettingsNavigationRow(
                        icon: "server.rack",
                        tint: .orange,
                        title: SettingsTextContent.verbatim(localized("Backend Trace")),
                        detail: nil,
                        value: "\(backendTraceEventCount)"
                    )
                }
                .noPressEffectButtonStyle()

                SettingsCardDivider()
                NavigationLink {
                    AIGenerationTraceView()
                } label: {
                    SettingsNavigationRow(
                        icon: "wand.and.stars.inverse",
                        tint: .purple,
                        title: SettingsTextContent.verbatim(localized("AI Generation Trace")),
                        detail: nil,
                        value: "\(aiGenerationTraceCount)"
                    )
                }
                .noPressEffectButtonStyle()

                SettingsCardDivider()
                NavigationLink {
                    RuntimeDiagnosticsView()
                } label: {
                    SettingsNavigationRow(
                        icon: "waveform.path.ecg.rectangle",
                        tint: .cyan,
                        title: SettingsTextContent.verbatim(localized("Runtime diagnostic reports")),
                        detail: nil,
                        value: nil
                    )
                }
                .noPressEffectButtonStyle()

                SettingsCardDivider()
                debugToggle(
                    icon: "square.grid.3x3",
                    title: "Deck grid guides",
                    detail: "Shows text measurement guides in deck cards.",
                    keyPath: \.deckGridTextLayoutDebugEnabled
                )
                SettingsCardDivider()
                debugToggle(
                    icon: "rectangle.inset.filled",
                    title: "Zone content guides",
                    detail: "Shows text-block guides inside card zones.",
                    keyPath: \.zoneContentLayoutDebugEnabled
                )
                SettingsCardDivider()
                debugToggle(
                    icon: "rectangle.and.text.magnifyingglass",
                    title: "Flashcard editor HUD",
                    detail: "Shows live authoring layout diagnostics.",
                    keyPath: \.zoneEditorDebugHUDEnabled
                )
                SettingsCardDivider()
                debugToggle(
                    icon: "questionmark.bubble",
                    title: "Quiz editor HUD",
                    detail: "Shows quiz scroll and caret diagnostics.",
                    keyPath: \.quizEditorDebugEnabled
                )
                SettingsCardDivider()
                debugToggle(
                    icon: "gamecontroller",
                    title: "Play mode controls",
                    detail: "Shows temporary controls in study modes.",
                    keyPath: \.playModeDeveloperModeEnabled
                )
                SettingsCardDivider()
                debugToggle(
                    icon: "rectangle.and.text.magnifyingglass",
                    title: "Library header debug",
                    detail: "Shows the copyable Library header layout report.",
                    keyPath: \.libraryHeaderLayoutDebugEnabled
                )
                SettingsCardDivider()
                debugToggle(
                    icon: "pin",
                    title: "Library sticky header trace",
                    detail: "Logs section-header pinning and handoff geometry.",
                    keyPath: \.libraryStickyHeaderDebugEnabled
                )
                SettingsCardDivider()
                debugToggle(
                    icon: "hand.tap",
                    title: "Window touch probe",
                    detail: "Logs global touch delivery and hit-test targets.",
                    keyPath: \.windowTouchProbeEnabled
                )
                SettingsCardDivider()
                debugToggle(
                    icon: "rectangle.bottomhalf.inset.filled",
                    title: "Sheet diagnostics",
                    detail: "Records custom-sheet lifecycle and touch events.",
                    keyPath: \.fullScreenSheetDiagnosticsEnabled
                )
                SettingsCardDivider()
                debugToggle(
                    icon: "person.badge.key",
                    title: "Authentication trace",
                    detail: "Requires relaunch to capture the complete startup flow.",
                    keyPath: \.authFlowDiagnosticsEnabled
                )
                SettingsCardDivider()
                debugToggle(
                    icon: "contextualmenu.and.cursorarrow",
                    title: "Context menu trace",
                    detail: "Logs custom context-menu gesture and placement events.",
                    keyPath: \.customContextMenuLoggingEnabled
                )
                SettingsCardDivider()
                debugToggle(
                    icon: "server.rack",
                    title: "Backend trace collection",
                    detail: "Records sanitized Firebase and subscription events.",
                    keyPath: \.backendTraceEnabled
                )
                SettingsCardDivider()
                debugToggle(
                    icon: "wand.and.stars.inverse",
                    title: "AI generation trace collection",
                    detail: "Records structured AI generation runs.",
                    keyPath: \.aiGenerationTraceEnabled
                )
                SettingsCardDivider()
                debugToggle(
                    icon: "doc.text.magnifyingglass",
                    title: "PDF import trace",
                    detail: "Records PDF picker, copy, and extraction stages.",
                    keyPath: \.pdfImportTraceEnabled
                )
                SettingsCardDivider()
                debugToggle(
                    icon: "rectangle.and.pencil.and.ellipsis",
                    title: "Editor runtime trace",
                    detail: "Records editor focus, keyboard, scroll, and layout events.",
                    keyPath: \.zoneEditorRuntimeTraceEnabled
                )
                SettingsCardDivider()
                debugToggle(
                    icon: "house.and.flag",
                    title: "Home layout trace",
                    detail: "Logs adaptive Home layout decisions when geometry changes.",
                    keyPath: \.homeLayoutTraceEnabled
                )
                SettingsCardDivider()
                debugToggle(
                    icon: "shadow",
                    title: "Edge shadow tuner",
                    detail: "Shows per-screen edge-shadow controls.",
                    keyPath: \.edgeShadowTuningEnabled
                )
                SettingsCardDivider()
                debugToggle(
                    icon: "wand.and.stars",
                    title: "Mock AI shortcut",
                    detail: "Shows the mock generation shortcut in the deck workspace.",
                    keyPath: \.deckWorkspaceMockAIEnabled
                )
                SettingsCardDivider()
                Button {
                    developmentPreferences.disableAllDiagnostics()
                } label: {
                    SettingsNavigationRow(
                        icon: "power",
                        tint: .red,
                        title: SettingsTextContent.verbatim(localized("Disable all diagnostics")),
                        detail: nil,
                        value: nil
                    )
                }
                .noPressEffectButtonStyle()
            }
        }
    }

    private func debugToggle(
        icon: String,
        title: String,
        detail: String,
        keyPath: ReferenceWritableKeyPath<DevelopmentPreferences, Bool>
    ) -> some View {
        SettingsToggleRow(
            icon: icon,
            tint: themeManager.accentColor.color,
            title: SettingsTextContent.verbatim(localized(title)),
            detail: SettingsTextContent.verbatim(localized(detail)),
            isOn: Binding(
                get: { developmentPreferences[keyPath: keyPath] },
                set: { developmentPreferences[keyPath: keyPath] = $0 }
            )
        )
    }

    private var navigationBar: some View {
        HStack {
            ChromeCircleIconButton(systemName: "chevron.compact.left") {
                dismiss()
            }

            Spacer()
        }
        .padding(.horizontal, UIConstants.Spacing.large)
        .padding(.top, UIConstants.Layout.deckNavigationTopPadding)
        .padding(.bottom, UIConstants.Spacing.small)
    }

    private var partialSheetBackgroundColorBinding: Binding<Color> {
        Binding(
            get: {
                Color(hex: developmentPreferences.partialSheetBackgroundHex)
                    ?? Color(hex: DevelopmentPreferences.defaultPartialSheetBackgroundHex)
                    ?? .black
            },
            set: { color in
                guard let hex = color.toHex() else { return }
                developmentPreferences.setPartialSheetBackgroundHex(hex)
            }
        )
    }

    private func localized(_ key: String) -> String {
        AppLocalization.string(key, locale: appPreferences.resolvedLocale)
    }
}
#endif
