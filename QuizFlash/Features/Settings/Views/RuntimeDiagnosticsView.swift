//
//  RuntimeDiagnosticsView.swift
//  QuizFlash
//
//  Copyable reports for bounded development-only runtime diagnostics.
//

#if QUIZFLASH_DEVELOPMENT
import SwiftUI
import UIKit

struct RuntimeDiagnosticsView: View {
    private enum ReportKind: String, CaseIterable, Identifiable {
        case authentication
        case sheets
        case pdfImport

        var id: Self { self }

        var title: String {
            switch self {
            case .authentication: "Authentication"
            case .sheets: "Sheets"
            case .pdfImport: "PDF Import"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    @State private var selectedReport: ReportKind = .authentication
    @State private var report = ""
    @State private var didCopy = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                SettingsSectionCard(
                    title: SettingsTextContent.verbatim(localized("Runtime diagnostic reports")),
                    subtitle: nil
                ) {
                    VStack(spacing: UIConstants.Spacing.standard) {
                        Picker("Report", selection: $selectedReport) {
                            ForEach(ReportKind.allCases) { kind in
                                Text(localized(kind.title)).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)

                        HStack(spacing: UIConstants.Spacing.standard) {
                            actionButton(
                                title: localized("Copy"),
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

                            actionButton(
                                title: localized("Refresh"),
                                icon: "arrow.clockwise",
                                tint: themeManager.accentColor.color
                            ) {
                                refresh()
                            }

                            actionButton(
                                title: localized("Clear"),
                                icon: "trash",
                                tint: .red
                            ) {
                                clearSelectedReport()
                            }
                        }
                    }
                }

                DiagnosticTraceTextView(text: report)
                    .frame(minHeight: 520)
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
            }
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.top, UIConstants.Spacing.large)
            .padding(.bottom, UIConstants.Spacing.huge)
        }
        .background(themeManager.groupedScreenBackground.ignoresSafeArea())
        .navigationTitle(localized("Runtime diagnostic reports"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                ChromeCircleIconButton(systemName: "chevron.compact.left") { dismiss() }
                Spacer()
            }
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.top, UIConstants.Layout.deckNavigationTopPadding)
            .padding(.bottom, UIConstants.Spacing.small)
        }
        .swipeBack { dismiss() }
        .task { refresh() }
        .onChange(of: selectedReport) { _, _ in refresh() }
    }

    private func refresh() {
        switch selectedReport {
        case .authentication:
            report = AuthFlowDebugTrace.report()
        case .sheets:
            report = FullScreenSheetTouchDiagnostics.shared.report()
        case .pdfImport:
            report = PDFImportDebugStore.report()
        }
    }

    private func clearSelectedReport() {
        switch selectedReport {
        case .authentication:
            AuthFlowDebugTrace.clear()
        case .sheets:
            FullScreenSheetTouchDiagnostics.shared.clear()
        case .pdfImport:
            PDFImportDebugStore.clear()
        }
        refresh()
    }

    private func actionButton(
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
                .padding(.vertical, UIConstants.Spacing.medium)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: UIConstants.Radius.medium))
        }
        .buttonStyle(.plain)
    }

    private func localized(_ key: String) -> String {
        AppLocalization.string(key, locale: appPreferences.resolvedLocale)
    }
}
#endif
