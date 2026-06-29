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
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @State private var didCopyPDFImportDebug = false
    @State private var didCopyZoneEditorDebug = false
    @State private var didCopyLastSheetDismissTrace = false
    @State private var didCopySheetDismissTraceHistory = false
    @State private var pdfImportDebugEventCount = PDFImportDebugStore.eventCount()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                buildModeSection
                themeSection
                if AppFeatures.current.showsInternalLabs {
                    flashcardDebugSection
                    quizDebugSection
                }
                if AppFeatures.current.showsVisualDebugOverlays {
                    visualDebuggingSection
                }
                if AppFeatures.current.enablesAITraceTooling {
                    aiUsageDebugSection
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
        .task {
            pdfImportDebugEventCount = PDFImportDebugStore.eventCount()
            await refreshAIUsageDebug()
        }
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
            title: "Visual Labs",
            subtitle: nil
        ) {
            SettingsToggleRow(
                icon: "sparkles.tv",
                tint: .cyan,
                title: "Edge Shadow Tuner",
                detail: "Shows the floating per-screen shadow tuning button while preserving each screen's saved values.",
                isOn: edgeShadowTuningEnabledBinding
            )

            SettingsCardDivider()

            SettingsToggleRow(
                icon: "rectangle.topthird.inset.filled",
                tint: .purple,
                title: "Custom Sheet Tuner",
                detail: "Shows one floating tuning panel that adjusts blur, top clearance, and scrim for every custom sheet at once.",
                isOn: customSheetTuningEnabledBinding
            )
        }
    }

    private var flashcardDebugSection: some View {
        SettingsSectionCard(
            title: "Flashcards",
            subtitle: nil
        ) {
            SettingsToggleRow(
                icon: "rectangle.dashed",
                tint: .orange,
                title: "Zone content guides",
                detail: nil,
                isOn: zoneContentLayoutDebugBinding
            )

            SettingsCardDivider()

            SettingsToggleRow(
                icon: "cursorarrow.motionlines",
                tint: .purple,
                title: "Editor debug HUD",
                detail: nil,
                isOn: zoneEditorDebugHUDBinding
            )

            SettingsCardDivider()

            Button {
                copyLastSheetDismissTraceReport()
            } label: {
                SettingsNavigationRow(
                    icon: didCopyLastSheetDismissTrace ? "checkmark" : "doc.text.magnifyingglass",
                    tint: .mint,
                    title: "Last Sheet Dismiss",
                    detail: "Copy only the newest sheet close trace.",
                    value: ZoneEditorDebugStore.shared.latestSheetDismissTraceSummary
                )
            }
            .buttonStyle(.plain)

            SettingsCardDivider()

            Button {
                copySheetDismissTraceHistoryReport()
            } label: {
                SettingsNavigationRow(
                    icon: didCopySheetDismissTraceHistory ? "checkmark" : "clock.arrow.circlepath",
                    tint: .orange,
                    title: "Dismiss Trace History",
                    detail: "Copy the recent sheet close sessions.",
                    value: ZoneEditorDebugStore.shared.hasSheetDismissTraceHistory ? "ready" : "none"
                )
            }
            .buttonStyle(.plain)

            SettingsCardDivider()

            Button {
                copyZoneEditorDebugReport()
            } label: {
                SettingsNavigationRow(
                    icon: didCopyZoneEditorDebug ? "checkmark" : "doc.on.doc",
                    tint: .purple,
                    title: "Zone Editor Debug",
                    detail: nil,
                    value: "\(ZoneEditorDebugStore.shared.eventCount)"
                )
            }
            .buttonStyle(.plain)

            SettingsCardDivider()

            SettingsToggleRow(
                icon: "rectangle.on.rectangle.square",
                tint: .yellow,
                title: "Deck grid guides",
                detail: nil,
                isOn: deckGridTextLayoutDebugBinding
            )
        }
    }

    private var quizDebugSection: some View {
        SettingsSectionCard(
            title: "Quiz",
            subtitle: nil
        ) {
            SettingsToggleRow(
                icon: "list.bullet.rectangle",
                tint: .orange,
                title: "Editor debug HUD",
                detail: nil,
                isOn: quizEditorDebugBinding
            )

            SettingsCardDivider()

            SettingsToggleRow(
                icon: "slider.horizontal.3",
                tint: .mint,
                title: "Play mode controls",
                detail: nil,
                isOn: playModeDeveloperModeEnabledBinding
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

    private var aiUsageDebugSection: some View {
        SettingsSectionCard(
            title: "AI Usage",
            subtitle: nil
        ) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                HStack(spacing: UIConstants.Spacing.small) {
                    Label("Usage debug", systemImage: "wand.and.stars")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: UIConstants.Spacing.small)

                    Button {
                        Task { @MainActor in
                            await refreshAIUsageDebug()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.purple)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                if let quota = subscriptionManager.cloudAIUsageQuotaForDisplay,
                   let limitMicroUSD = quota.limitMicroUSD,
                   limitMicroUSD > 0 {
                    Text("\(formattedUsagePercent(quota.usageProgress)) · \(formattedMicroUSD(quota.consumedMicroUSD + quota.reservedMicroUSD)) / \(formattedMicroUSD(limitMicroUSD))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                if subscriptionManager.cloudAIGenerationHistory.isEmpty {
                    Text("No generations yet")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: UIConstants.Spacing.small) {
                            ForEach(subscriptionManager.cloudAIGenerationHistory) { generation in
                                aiGenerationDebugRow(generation)
                            }
                        }
                        .padding(.trailing, UIConstants.Spacing.small)
                    }
                    .frame(height: 280)
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
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

            SettingsToggleRow(
                icon: "bolt.badge.clock",
                tint: .blue,
                title: "Mock AI Shortcut",
                detail: "Shows the deck workspace mock generation control for local seed data.",
                isOn: deckWorkspaceMockAIEnabledBinding
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

            Button {
                copyPDFImportDebugReport()
            } label: {
                SettingsNavigationRow(
                    icon: didCopyPDFImportDebug ? "checkmark" : "doc.on.doc",
                    tint: .orange,
                    title: "PDF Import Debug",
                    detail: "Copy picker and import events for LiveContainer diagnosis.",
                    value: "\(pdfImportDebugEventCount)"
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

    private func refreshAIUsageDebug() async {
        await subscriptionManager.refreshCloudAIUsageQuota()
        await subscriptionManager.refreshCloudAIGenerationHistory()
    }

    private func aiGenerationDebugRow(_ generation: CloudAIGenerationUsageRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: UIConstants.Spacing.small) {
                Text(generation.status.uppercased())
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.purple)
                    .lineLimit(1)

                Spacer(minLength: UIConstants.Spacing.small)

                Text(formattedMicroUSD(generation.costMicroUSD))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            HStack(spacing: UIConstants.Spacing.small) {
                debugMetric("tokens", generation.totalTokens)
                debugMetric("in", generation.promptTokens)
                debugMetric("out", generation.completionTokens)
                debugMetric("cards", "\(generation.validatedCards)/\(generation.targetCards)")
            }

            HStack(spacing: UIConstants.Spacing.small) {
                debugMetric("hit", generation.cacheHitTokens)
                debugMetric("miss", generation.cacheMissTokens)

                Spacer(minLength: UIConstants.Spacing.small)

                Text(debugDate(generation.createdAtMs))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func debugMetric(_ title: String, _ value: Int) -> some View {
        debugMetric(title, "\(value)")
    }

    private func debugMetric(_ title: String, _ value: String) -> some View {
        Text("\(title) \(value)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private func formattedMicroUSD(_ value: Int) -> String {
        let amount = Double(max(value, 0)) / 1_000_000
        return amount.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    private func formattedUsagePercent(_ progress: Double) -> String {
        let boundedProgress = max(0, min(progress, 1))
        return boundedProgress.formatted(.percent.precision(.fractionLength(0)))
    }

    private func debugDate(_ milliseconds: Int) -> String {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
            .formatted(date: .abbreviated, time: .shortened)
    }

    private func copyPDFImportDebugReport() {
        UIPasteboard.general.string = PDFImportDebugStore.report()
        pdfImportDebugEventCount = PDFImportDebugStore.eventCount()
        didCopyPDFImportDebug = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            didCopyPDFImportDebug = false
        }
    }

    private func copyZoneEditorDebugReport() {
        UIPasteboard.general.string = ZoneEditorDebugStore.shared.report
        didCopyZoneEditorDebug = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            didCopyZoneEditorDebug = false
        }
    }

    private func copyLastSheetDismissTraceReport() {
        UIPasteboard.general.string = ZoneEditorDebugStore.shared.latestSheetDismissTraceReport
        didCopyLastSheetDismissTrace = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            didCopyLastSheetDismissTrace = false
        }
    }

    private func copySheetDismissTraceHistoryReport() {
        UIPasteboard.general.string = ZoneEditorDebugStore.shared.sheetDismissTraceHistoryReport
        didCopySheetDismissTraceHistory = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            didCopySheetDismissTraceHistory = false
        }
    }

    private var deckGridTextLayoutDebugBinding: Binding<Bool> {
        Binding(
            get: { developmentPreferences.deckGridTextLayoutDebugEnabled },
            set: { developmentPreferences.deckGridTextLayoutDebugEnabled = $0 }
        )
    }

    private var zoneContentLayoutDebugBinding: Binding<Bool> {
        Binding(
            get: { developmentPreferences.zoneContentLayoutDebugEnabled },
            set: { developmentPreferences.zoneContentLayoutDebugEnabled = $0 }
        )
    }

    private var zoneEditorDebugHUDBinding: Binding<Bool> {
        Binding(
            get: { developmentPreferences.zoneEditorDebugHUDEnabled },
            set: { developmentPreferences.zoneEditorDebugHUDEnabled = $0 }
        )
    }

    private var quizEditorDebugBinding: Binding<Bool> {
        Binding(
            get: { developmentPreferences.quizEditorDebugEnabled },
            set: { developmentPreferences.quizEditorDebugEnabled = $0 }
        )
    }

    private var aiDebugTracingEnabledBinding: Binding<Bool> {
        Binding(
            get: { developmentPreferences.aiDebugTracingEnabled },
            set: { developmentPreferences.aiDebugTracingEnabled = $0 }
        )
    }

    private var deckWorkspaceMockAIEnabledBinding: Binding<Bool> {
        Binding(
            get: { developmentPreferences.deckWorkspaceMockAIEnabled },
            set: { developmentPreferences.deckWorkspaceMockAIEnabled = $0 }
        )
    }

    private var playModeDeveloperModeEnabledBinding: Binding<Bool> {
        Binding(
            get: { developmentPreferences.playModeDeveloperModeEnabled },
            set: { developmentPreferences.playModeDeveloperModeEnabled = $0 }
        )
    }

    private var edgeShadowTuningEnabledBinding: Binding<Bool> {
        Binding(
            get: { developmentPreferences.edgeShadowTuningEnabled },
            set: { developmentPreferences.edgeShadowTuningEnabled = $0 }
        )
    }

    private var customSheetTuningEnabledBinding: Binding<Bool> {
        Binding(
            get: { developmentPreferences.customSheetTuningEnabled },
            set: { developmentPreferences.customSheetTuningEnabled = $0 }
        )
    }
}
