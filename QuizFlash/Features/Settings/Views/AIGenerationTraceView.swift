//
//  AIGenerationTraceView.swift
//  QuizFlash
//
//  Copyable diagnostics for complete AI generation runs.
//

#if DEBUG
import SwiftUI
import UIKit

/// Lists persistent AI generation runs and exposes their structured JSON export.
struct AIGenerationTraceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppPreferences.self) private var appPreferences

    @State private var runs: [AIDebugTraceRunSummary] = []
    @State private var selectedRunID: UUID?
    @State private var report = ""
    @State private var didCopy = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                actionsCard
                runsCard
                reportCard
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.top, UIConstants.Spacing.large)
            .padding(.bottom, UIConstants.Spacing.huge)
        }
        .background(themeManager.groupedScreenBackground.ignoresSafeArea())
        .navigationTitle(localized("AI Generation Trace"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            navigationBar
        }
        .swipeBack { dismiss() }
        .task {
            await loadReport()
        }
    }

    private var actionsCard: some View {
        SettingsSectionCard(
            title: SettingsTextContent.verbatim(localized("AI Generation Trace")),
            subtitle: nil
        ) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                HStack(spacing: UIConstants.Spacing.standard) {
                    traceActionButton(
                        title: localized("Copy"),
                        icon: didCopy ? "checkmark" : "doc.on.doc",
                        tint: .green
                    ) {
                        guard !report.isEmpty else { return }
                        UIPasteboard.general.string = report
                        didCopy = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            didCopy = false
                        }
                    }

                    traceActionButton(
                        title: localized("Refresh"),
                        icon: "arrow.clockwise",
                        tint: themeManager.accentColor.color
                    ) {
                        Task { await loadReport(preferredRunID: selectedRunID) }
                    }

                    traceActionButton(
                        title: localized("Clear"),
                        icon: "trash",
                        tint: .red
                    ) {
                        Task {
                            await AIDebugTraceStore.shared.clearAllTraces()
                            await loadReport()
                        }
                    }
                }

                Text("\(runs.count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(themeManager.textSecondary)
            }
        }
    }

    private var runsCard: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text(localized("Trace Sessions"))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(themeManager.textPrimary)

            if runs.isEmpty {
                Text(localized("No trace sessions"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(themeManager.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, UIConstants.Spacing.small)
            } else {
                LazyVStack(spacing: UIConstants.Spacing.small) {
                    ForEach(runs) { run in
                        runRow(run)
                    }
                }
            }
        }
        .padding(UIConstants.Spacing.large)
        .settingsCardBackground(cornerRadius: UIConstants.Radius.large)
    }

    private var reportCard: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text(localized("Trace Log"))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(themeManager.textPrimary)

            DiagnosticTraceTextView(text: report)
                .frame(minHeight: 520)
                .background(
                    RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
        }
        .padding(UIConstants.Spacing.large)
        .settingsCardBackground(cornerRadius: UIConstants.Radius.large)
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

    private func runRow(_ run: AIDebugTraceRunSummary) -> some View {
        let isSelected = selectedRunID == run.id
        let target = run.targetCount.map(String.init) ?? "–"
        let detail = "\(run.status) · \(run.targetType) · \(target) · \(run.eventCount)"

        return Button {
            Task {
                selectedRunID = run.id
                await loadReport(preferredRunID: run.id)
            }
        } label: {
            HStack(spacing: UIConstants.Spacing.standard) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isSelected ? themeManager.accentColor.color : statusColor(for: run.status))

                VStack(alignment: .leading, spacing: UIConstants.Spacing.tiny) {
                    Text(run.createdAt.formatted(.dateTime.year().month().day().hour().minute().second()))
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(themeManager.textPrimary)

                    Text(detail)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(themeManager.textSecondary)
                }

                Spacer(minLength: UIConstants.Spacing.small)
            }
            .padding(.horizontal, UIConstants.Spacing.medium)
            .padding(.vertical, UIConstants.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                    .fill(
                        isSelected
                            ? themeManager.accentColor.color.opacity(0.16)
                            : Color(uiColor: .secondarySystemGroupedBackground)
                    )
            )
        }
        .noPressEffectButtonStyle()
    }

    private func traceActionButton(
        title: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(tint.opacity(0.14), in: Capsule())
        }
        .noPressEffectButtonStyle()
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "completed": return .green
        case "failed": return .red
        default: return .orange
        }
    }

    private func loadReport() async {
        await loadReport(preferredRunID: selectedRunID)
    }

    private func loadReport(preferredRunID: UUID?) async {
        let loadedRuns = await AIDebugTraceStore.shared.listRuns()
            .filter { $0.kind == .generation }
        let resolvedRunID = preferredRunID.flatMap { runID in
            loadedRuns.contains { $0.id == runID } ? runID : nil
        } ?? loadedRuns.first?.id

        runs = loadedRuns
        selectedRunID = resolvedRunID
        if let resolvedRunID,
           let detail = await AIDebugTraceStore.shared.loadRunDetail(id: resolvedRunID) {
            report = detail.jsonString
        } else {
            report = ""
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.string(key, locale: appPreferences.resolvedLocale)
    }
}
#endif
