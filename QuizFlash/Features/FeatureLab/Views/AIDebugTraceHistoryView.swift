//
//  AIDebugTraceHistoryView.swift
//  QuizFlash
//
//  Development-only history browser for persisted AI generation traces.
//

import SwiftUI

private let kAIDebugTraceHistoryChromeSpace = "AIDebugTraceHistoryChromeSpace"

struct AIDebugTraceHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @State private var isCollapsedTitleVisible = false
    @State private var navigationBarHeight: CGFloat =
        UIConstants.Size.capsuleHeight + UIConstants.Layout.deckNavigationTopPadding
    @State private var navigationBarBottomY: CGFloat = 0
    @State private var runs: [AIDebugTraceRunSummary] = []
    @State private var isLoading = true

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                themeManager.groupedScreenBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                        LargeScreenTitle(title: "AI Trace History")
                            .collapsibleTitleRevealAnchor(
                                in: kAIDebugTraceHistoryChromeSpace,
                                navigationBarBottomY: navigationBarBottomY,
                                revealClearance: SettingsChromeMetrics.pillRevealClearance,
                                isVisible: $isCollapsedTitleVisible
                            )

                        SettingsInfoCard(
                            icon: "waveform.and.magnifyingglass",
                            tint: .orange,
                            text: "Open any run to inspect the full JSON trace for generation, including requests, raw responses, retries, malformed payloads, and decode steps."
                        )

                        if isLoading {
                            SettingsSectionCard(
                                title: "Runs",
                                subtitle: "Loading persisted AI trace history."
                            ) {
                                ProgressActivityDots()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else if runs.isEmpty {
                            SettingsSectionCard(
                                title: "Runs",
                                subtitle: "No trace runs have been recorded yet."
                            ) {
                                Text("Enable verbose AI tracing, generate cards, then come back here to inspect the complete JSON history for each run.")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            SettingsSectionCard(
                                title: "Runs",
                                subtitle: "\(runs.count) recorded \(runs.count == 1 ? "run" : "runs"), newest first."
                            ) {
                                ForEach(Array(runs.enumerated()), id: \.element.id) { index, run in
                                    NavigationLink {
                                        AIDebugTraceRunDetailView(runID: run.id)
                                    } label: {
                                        SettingsNavigationRow(
                                            icon: icon(for: run.kind),
                                            tint: tint(for: run.kind),
                                            title: title(for: run),
                                            detail: detail(for: run),
                                            value: value(for: run)
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    if index < runs.count - 1 {
                                        SettingsCardDivider()
                                    }
                                }
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
                .refreshable {
                    await loadRuns()
                }
            }
            .screenTopEdgeShadow(
                topHeight: structuralTopEdgeShadowHeight,
                topRevealProgress: isCollapsedTitleVisible ? 1 : 0,
                debugScreenID: "featurelab.ai-trace-history",
                style: .progressiveBlur()
            )

            navigationBar
        }
        .coordinateSpace(name: kAIDebugTraceHistoryChromeSpace)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .task {
            await loadRuns()
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
            coordinateSpaceName: kAIDebugTraceHistoryChromeSpace,
            onHeightChange: { navigationBarHeight = $0 },
            onBottomChange: { navigationBarBottomY = $0 }
        ) {
            ChromeCircleIconButton(systemName: "chevron.left") {
                dismiss()
            }
        } center: { maxWidth in
            CollapsibleTitlePill(
                title: "AI Trace History",
                maxWidth: maxWidth,
                isVisible: isCollapsedTitleVisible
            )
        } trailing: {
            ChromeCircleIconButton(systemName: "arrow.clockwise") {
                Task {
                    await loadRuns()
                }
            }
        }
    }

    private func loadRuns() async {
        isLoading = true
        runs = await AIDebugTraceStore.shared.listRuns()
        isLoading = false
    }

    private func icon(for kind: AIDebugRunKind) -> String {
        switch kind {
        case .generation:
            return "sparkles.rectangle.stack.fill"
        case .utility:
            return "wrench.and.screwdriver.fill"
        }
    }

    private func tint(for kind: AIDebugRunKind) -> Color {
        switch kind {
        case .generation:
            return .orange
        case .utility:
            return .gray
        }
    }

    private func title(for run: AIDebugTraceRunSummary) -> String {
        "\(run.kind.rawValue.capitalized) • \(run.targetType.capitalized)"
    }

    private func detail(for run: AIDebugTraceRunSummary) -> String {
        var parts: [String] = [
            run.providerName,
            run.sourceKind.capitalized,
            "\(run.eventCount) events",
            Self.dateFormatter.string(from: run.createdAt)
        ]

        if let targetCount = run.targetCount {
            parts.insert("\(targetCount) target", at: 2)
        }

        return parts.joined(separator: " • ")
    }

    private func value(for run: AIDebugTraceRunSummary) -> String {
        switch run.status {
        case "completed":
            return "Done"
        case "failed":
            return "Failed"
        default:
            return "Active"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
