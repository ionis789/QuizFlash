//
//  AIDebugTraceRunDetailView.swift
//  QuizFlash
//
//  Development-only JSON viewer for a persisted AI debug trace run.
//

import SwiftUI
import UIKit

private let kAIDebugTraceDetailChromeSpace = "AIDebugTraceDetailChromeSpace"

struct AIDebugTraceRunDetailView: View {
    let runID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @State private var isCollapsedTitleVisible = false
    @State private var navigationBarHeight: CGFloat =
        UIConstants.Size.capsuleHeight + UIConstants.Layout.deckNavigationTopPadding
    @State private var navigationBarBottomY: CGFloat = 0
    @State private var detail: AIDebugTraceRunDetail?
    @State private var isLoading = true
    @State private var didCopyJSON = false

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                themeManager.groupedScreenBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                        LargeScreenTitle(title: "AI Trace JSON")
                            .collapsibleTitleRevealAnchor(
                                in: kAIDebugTraceDetailChromeSpace,
                                navigationBarBottomY: navigationBarBottomY,
                                revealClearance: SettingsChromeMetrics.pillRevealClearance,
                                isVisible: $isCollapsedTitleVisible
                            )

                        if isLoading {
                            SettingsSectionCard(
                                title: "Trace",
                                subtitle: "Loading full AI trace payload."
                            ) {
                                ProgressActivityDots()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else if let detail {
                            summaryCard(detail.summary)
                            jsonCard(detail.jsonString)
                        } else {
                            SettingsSectionCard(
                                title: "Trace",
                                subtitle: "This AI trace run is no longer available."
                            ) {
                                Text("The persisted JSON trace could not be loaded. It may have been deleted or corrupted.")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
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
                debugScreenID: "featurelab.ai-trace-run-detail",
                style: .progressiveBlur()
            )

            navigationBar
        }
        .coordinateSpace(name: kAIDebugTraceDetailChromeSpace)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .task {
            await loadDetail()
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
            coordinateSpaceName: kAIDebugTraceDetailChromeSpace,
            onHeightChange: { navigationBarHeight = $0 },
            onBottomChange: { navigationBarBottomY = $0 }
        ) {
            ChromeCircleIconButton(systemName: "chevron.left") {
                dismiss()
            }
        } center: { maxWidth in
            CollapsibleTitlePill(
                title: "AI Trace JSON",
                maxWidth: maxWidth,
                isVisible: isCollapsedTitleVisible
            )
        } trailing: {
            ChromeCircleIconButton(systemName: didCopyJSON ? "checkmark" : "doc.on.doc") {
                guard let detail else { return }
                UIPasteboard.general.string = detail.jsonString
                didCopyJSON = true
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    didCopyJSON = false
                }
            }
        }
    }

    private func loadDetail() async {
        isLoading = true
        detail = await AIDebugTraceStore.shared.loadRunDetail(id: runID)
        isLoading = false
    }

    private func summaryCard(_ summary: AIDebugTraceRunSummary) -> some View {
        SettingsSectionCard(
            title: "\(summary.kind.rawValue.capitalized) • \(summary.targetType.capitalized)",
            subtitle: "Provider \(summary.providerName) • \(summary.eventCount) events • \(Self.dateFormatter.string(from: summary.createdAt))"
        ) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                traceMetaRow("Source", summary.sourceKind.capitalized)
                if let targetCount = summary.targetCount {
                    traceMetaRow("Target Count", "\(targetCount)")
                }
                if let sourceCount = summary.sourceCount {
                    traceMetaRow("Source Count", "\(sourceCount)")
                }
                if let modelName = summary.modelName, !modelName.isEmpty {
                    traceMetaRow("Model", modelName)
                }
                if let durationMilliseconds = summary.durationMilliseconds {
                    traceMetaRow("Duration", Self.durationFormatter(milliseconds: durationMilliseconds))
                }
                traceMetaRow("Status", summary.status.capitalized)
                if let lastStage = summary.lastStage, !lastStage.isEmpty {
                    traceMetaRow("Last Stage", lastStage)
                }
            }
        }
    }

    private func jsonCard(_ jsonString: String) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HStack {
                Text("Trace JSON")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                Text("Copy and share with Codex")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            TraceJSONTextView(text: jsonString)
                .frame(minHeight: 420)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .padding(UIConstants.Spacing.large)
        .settingsCardBackground(cornerRadius: UIConstants.Radius.large)
    }

    private func traceMetaRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: UIConstants.Spacing.medium) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 98, alignment: .leading)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    private static func durationFormatter(milliseconds: Int) -> String {
        let totalSeconds = max(0, milliseconds / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let millisecondsRemainder = max(0, milliseconds % 1000)

        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }

        if totalSeconds > 0 {
            return "\(totalSeconds).\(String(format: "%03d", millisecondsRemainder))s"
        }

        return "\(milliseconds) ms"
    }
}

private struct TraceJSONTextView: UIViewRepresentable {
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
                .paragraphStyle: paragraphStyle
            ]
        )
    }
}
