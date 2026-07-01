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
        report = await BackendTraceStore.shared.report()
        eventCount = await BackendTraceStore.shared.eventCount()
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
