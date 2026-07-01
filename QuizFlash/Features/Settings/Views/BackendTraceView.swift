//
//  BackendTraceView.swift
//  QuizFlash
//
//  Copyable backend communication diagnostics.
//

import SwiftUI
import UIKit

// MARK: - Backend Trace View

struct BackendTraceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppPreferences.self) private var appPreferences

    @State private var report = ""
    @State private var eventCount = 0
    @State private var sessions: [BackendTraceSessionSummary] = []
    @State private var selectedSessionID: UUID?
    @State private var didCopy = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                SettingsSectionCard(
                    title: SettingsTextContent.verbatim(AppLocalization.string("Backend Trace", locale: appPreferences.resolvedLocale)),
                    subtitle: nil
                ) {
                    VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
                        HStack(spacing: UIConstants.Spacing.standard) {
                            traceActionButton(
                                title: AppLocalization.string("Copy", locale: appPreferences.resolvedLocale),
                                icon: didCopy ? "checkmark" : "doc.on.doc",
                                tint: .green
                            ) {
                                UIPasteboard.general.string = report
                                didCopy = true
                                Task {
                                    try? await Task.sleep(for: .seconds(1.2))
                                    didCopy = false
                                }
                            }

                            traceActionButton(
                                title: AppLocalization.string("Refresh", locale: appPreferences.resolvedLocale),
                                icon: "arrow.clockwise",
                                tint: themeManager.accentColor.color
                            ) {
                                Task { await loadReport() }
                            }

                            traceActionButton(
                                title: AppLocalization.string("Clear", locale: appPreferences.resolvedLocale),
                                icon: "trash",
                                tint: .red
                            ) {
                                Task {
                                    await BackendTraceStore.shared.clear()
                                    await loadReport()
                                }
                            }
                        }

                        Text("\(eventCount)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(themeManager.textSecondary)
                    }
                }

                traceSessionsCard
                traceReportCard
            }
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.top, UIConstants.Spacing.large)
            .padding(.bottom, UIConstants.Spacing.huge)
        }
        .background(themeManager.groupedScreenBackground.ignoresSafeArea())
        .navigationTitle(AppLocalization.string("Backend Trace", locale: appPreferences.resolvedLocale))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            settingsNavigationBar
        }
        .swipeBack { dismiss() }
        .task {
            await loadReport()
        }
    }

    private var settingsNavigationBar: some View {
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

    private var traceReportCard: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text(AppLocalization.string("Trace Log", locale: appPreferences.resolvedLocale))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(themeManager.textPrimary)

            BackendTraceTextView(text: report)
                .frame(minHeight: 520)
                .background(
                    RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
        }
        .padding(UIConstants.Spacing.large)
        .settingsCardBackground(cornerRadius: UIConstants.Radius.large)
    }

    private var traceSessionsCard: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text(AppLocalization.string("Trace Sessions", locale: appPreferences.resolvedLocale))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(themeManager.textPrimary)

            if sessions.isEmpty {
                Text(AppLocalization.string("No trace sessions", locale: appPreferences.resolvedLocale))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(themeManager.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, UIConstants.Spacing.small)
            } else {
                VStack(spacing: UIConstants.Spacing.small) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        traceSessionRow(session, index: index)
                    }
                }
            }
        }
        .padding(UIConstants.Spacing.large)
        .settingsCardBackground(cornerRadius: UIConstants.Radius.large)
    }

    private func traceSessionRow(
        _ session: BackendTraceSessionSummary,
        index: Int
    ) -> some View {
        let isSelected = selectedSessionID == session.id
        let title = session.isCurrent
            ? AppLocalization.string("Current Session", locale: appPreferences.resolvedLocale)
            : "\(AppLocalization.string("Session", locale: appPreferences.resolvedLocale)) \(sessions.count - index)"

        return Button {
            Task {
                selectedSessionID = session.id
                await loadReport(preferredSessionID: session.id)
            }
        } label: {
            HStack(spacing: UIConstants.Spacing.standard) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isSelected ? themeManager.accentColor.color : themeManager.textSecondary)

                VStack(alignment: .leading, spacing: UIConstants.Spacing.tiny) {
                    Text(title)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(themeManager.textPrimary)

                    Text("\(session.updatedAt.formatted(.dateTime.hour().minute().second())) · \(session.eventCount)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(themeManager.textSecondary)
                }

                Spacer(minLength: UIConstants.Spacing.small)
            }
            .padding(.horizontal, UIConstants.Spacing.medium)
            .padding(.vertical, UIConstants.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                    .fill(isSelected ? themeManager.accentColor.color.opacity(0.16) : Color(uiColor: .secondarySystemGroupedBackground))
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

    private func loadReport() async {
        await loadReport(preferredSessionID: selectedSessionID)
    }

    private func loadReport(preferredSessionID: UUID?) async {
        let loadedSessions = await BackendTraceStore.shared.sessionSummaries()
        let resolvedSessionID = preferredSessionID.flatMap { sessionID in
            loadedSessions.contains { $0.id == sessionID } ? sessionID : nil
        } ?? loadedSessions.first?.id

        sessions = loadedSessions
        selectedSessionID = resolvedSessionID
        report = await BackendTraceStore.shared.report(sessionID: resolvedSessionID)
        eventCount = loadedSessions.first { $0.id == resolvedSessionID }?.eventCount ?? 0
    }
}

private struct BackendTraceTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        textView.textContainer.lineFragmentPadding = 0
        textView.alwaysBounceVertical = true
        textView.showsVerticalScrollIndicator = true
        textView.showsHorizontalScrollIndicator = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byCharWrapping
        paragraphStyle.lineSpacing = 3

        textView.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraphStyle,
            ]
        )
    }
}
