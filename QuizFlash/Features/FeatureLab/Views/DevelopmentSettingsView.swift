//
//  DevelopmentSettingsView.swift
//  QuizFlash
//
//  Centralized hub for developer-only toggles, AI diagnostics, and visual labs.
//

import SwiftUI

struct DevelopmentSettingsView: View {
    @Environment(DevelopmentPreferences.self) private var developmentPreferences
    @Environment(AIProviderStore.self) private var aiProviderStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                buildModeSection
                themeSection
                if AppFeatures.current.showsInternalLabs {
                    playModeSection
                }
                if AppFeatures.current.showsVisualDebugOverlays {
                    visualDebuggingSection
                }
                if AppFeatures.current.enablesAITraceTooling {
                    aiToolingSection
                }
            }
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.top, UIConstants.Spacing.large)
            .padding(.bottom, UIConstants.Size.bottomChromeBarHeight + 120)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Development")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var buildModeSection: some View {
        SettingsSectionCard(
            title: "Build",
            subtitle: nil
        ) {
            HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
                ZStack {
                    RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                        .fill(Color.cyan.opacity(0.16))
                        .frame(width: 44, height: 44)

                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.cyan)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Mode")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)

                Text(AppBuildConfiguration.current.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.cyan.opacity(0.16), in: Capsule())
            }
        }
    }

    private var visualDebuggingSection: some View {
        SettingsSectionCard(
            title: "Debug",
            subtitle: nil
        ) {
            SettingsToggleRow(
                icon: "rectangle.on.rectangle.square",
                tint: .yellow,
                title: "Deck Grid Guides",
                detail: nil,
                isOn: deckGridTextLayoutDebugBinding
            )
        }
    }

    private var themeSection: some View {
        SettingsSectionCard(
            title: "Theme",
            subtitle: nil
        ) {
            NavigationLink {
                DevelopmentThemeStudioView()
            } label: {
                SettingsNavigationRow(
                    icon: "paintpalette.fill",
                    tint: .pink,
                    title: "Theme Studio",
                    detail: "Live-edit semantic color tokens and preview the result immediately.",
                    value: nil
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var playModeSection: some View {
        SettingsSectionCard(
            title: "Play Mode",
            subtitle: nil
        ) {
            SettingsToggleRow(
                icon: "slider.horizontal.3",
                tint: .mint,
                title: "Developer Controls",
                detail: "Shows the in-game debug settings button used for swipe-progress inspection and temporary tuning.",
                isOn: playModeDeveloperModeEnabledBinding
            )
        }
    }

    private var aiToolingSection: some View {
        SettingsSectionCard(
            title: "AI",
            subtitle: nil
        ) {
            NavigationLink {
                AIProviderSettingsView()
            } label: {
                SettingsNavigationRow(
                    icon: "sparkles.rectangle.stack.fill",
                    tint: .purple,
                    title: "Provider",
                    detail: nil,
                    value: aiProviderStore.activeProfile?.trimmedName ?? "Not Configured"
                )
            }
            .buttonStyle(.plain)

            SettingsCardDivider()

            SettingsToggleRow(
                icon: "waveform.and.magnifyingglass",
                tint: .orange,
                title: "Verbose Trace",
                detail: nil,
                isOn: aiDebugTracingEnabledBinding
            )

            SettingsCardDivider()

            NavigationLink {
                AIDebugTraceHistoryView()
            } label: {
                SettingsNavigationRow(
                    icon: "clock.arrow.circlepath",
                    tint: .blue,
                    title: "Trace History",
                    detail: nil,
                    value: nil
                )
            }
            .buttonStyle(.plain)

            SettingsCardDivider()

            NavigationLink {
                LatexSymbolLabView()
            } label: {
                SettingsNavigationRow(
                    icon: "function",
                    tint: .green,
                    title: "LaTeX Symbol Lab",
                    detail: nil,
                    value: nil
                )
            }
            .buttonStyle(.plain)

            SettingsCardDivider()

            Button(role: .destructive) {
                Task {
                    await AIDebugTraceStore.shared.clearAllTraces()
                }
            } label: {
                SettingsNavigationRow(
                    icon: "trash.fill",
                    tint: .red,
                    title: "Clear Traces",
                    detail: nil,
                    value: nil
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var deckGridTextLayoutDebugBinding: Binding<Bool> {
        Binding(
            get: { developmentPreferences.deckGridTextLayoutDebugEnabled },
            set: { developmentPreferences.deckGridTextLayoutDebugEnabled = $0 }
        )
    }

    private var aiDebugTracingEnabledBinding: Binding<Bool> {
        Binding(
            get: { developmentPreferences.aiDebugTracingEnabled },
            set: { developmentPreferences.aiDebugTracingEnabled = $0 }
        )
    }

    private var playModeDeveloperModeEnabledBinding: Binding<Bool> {
        Binding(
            get: { developmentPreferences.playModeDeveloperModeEnabled },
            set: { developmentPreferences.playModeDeveloperModeEnabled = $0 }
        )
    }
}
