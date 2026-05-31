//
//  LearnModeView.swift
//  QuizFlash
//
//  Guided study report built from deck card previews and review history.
//

import SwiftUI
import SwiftData

// MARK: - Learn Mode View

/// A read-only deck briefing that groups weak areas, fresh material, and card coverage.
struct LearnModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var context

    /// The deck forwarded from `DeckView`.
    let deck: DeckModel
    let safeAreaInsets: UIEdgeInsets
    let availability: PlayModeCardAvailability

    @State private var viewModel: LearnModeViewModel
    @State private var headerHeight: CGFloat = 0

    init(deck: DeckModel, safeAreaInsets: UIEdgeInsets, availability: PlayModeCardAvailability) {
        self.deck = deck
        self.safeAreaInsets = safeAreaInsets
        self.availability = availability
        _viewModel = State(initialValue: LearnModeViewModel(deck: deck))
    }

    private var accentColor: Color { ThemeManager.shared.accentColor.color }

    private var deckColor: Color {
        Color(hex: deck.colorHex) ?? accentColor
    }

    private var horizontalInset: CGFloat {
        horizontalSizeClass == .compact
            ? UIConstants.Layout.compactScreenEdgeInset
            : UIConstants.Layout.screenEdgeInset
    }

    private var report: LearnModeReport {
        viewModel.report
    }

    private var learnSettings: LearnModeSettings {
        deck.playModeSettings?.learnSettings ?? LearnModeSettings()
    }

    private var insightLimit: Int {
        switch learnSettings.density {
        case .compact:  return 2
        case .standard: return 4
        case .detailed: return 6
        }
    }

    private var heroHeadline: String {
        if report.totalCards == 0 {
            return "This deck is still empty."
        }
        if report.dueCards > 0 {
            return "Start with \(report.dueCards) card\(report.dueCards == 1 ? "" : "s") that need a refresh."
        }
        if report.newCards > 0 {
            return "Begin with \(report.newCards) new card\(report.newCards == 1 ? "" : "s") and set the baseline."
        }
        if report.buildingCards > 0 {
            return "Most of this deck is still in active rotation."
        }
        return "This deck is largely in maintenance mode."
    }

    private var heroSupportingCopy: String {
        if report.totalCards == 0 {
            return "Add cards first, then Learn mode can turn the deck into a guided study briefing."
        }

        let reviewedSummary = report.reviewedCards == 0
            ? "No cards have review history yet."
            : "\(report.reviewedCards) card\(report.reviewedCards == 1 ? "" : "s") already have review history with \(report.reviewAccuracy)% accuracy."

        if report.stableCards > 0 {
            return "\(reviewedSummary) \(report.stableCards) card\(report.stableCards == 1 ? "" : "s") look stable enough for a skim-only pass."
        }

        return reviewedSummary
    }

    var body: some View {
        GeometryReader { geo in
            let resolvedSafeTopInset = max(safeAreaInsets.top, geo.safeAreaInsets.top)
            let resolvedSafeBottomInset = max(safeAreaInsets.bottom, geo.safeAreaInsets.bottom)

            ZStack(alignment: .top) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                        overviewCard
                        stageBreakdownCard

                        if let errorMessage = viewModel.errorMessage {
                            errorCard(message: errorMessage)
                        } else if viewModel.isLoading && report == .empty {
                            loadingCard
                        } else {
                            configuredSections
                        }
                    }
                    .padding(.horizontal, horizontalInset)
                    .padding(.top, headerHeight + UIConstants.Spacing.large)
                    .padding(.bottom, resolvedSafeBottomInset + UIConstants.Spacing.huge)
                }

                header(safeTopInset: resolvedSafeTopInset)
            }
            .fullScreenSheetDragActivationHeight(headerHeight)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: deck.persistentModelID) {
            viewModel.loadIfNeeded(container: context.container)
        }
        .onDisappear {
            viewModel.tearDown()
        }
    }

    // MARK: - Header

    private func header(safeTopInset: CGFloat) -> some View {
        VStack(spacing: UIConstants.Spacing.small) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 56, height: 5)
                .accessibilityHidden(true)

            ZStack {
                VStack(spacing: 2) {
                    Text("Learn")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(deck.title.uppercased())
                        .font(.system(size: UIConstants.Size.navigationChromeLabel, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Spacer(minLength: 0)
                    dismissButton
                        .frame(width: UIConstants.Size.actionButton, alignment: .trailing)
                }
            }
            .frame(height: UIConstants.Size.capsuleHeight)
        }
        .padding(.top, safeTopInset + UIConstants.Spacing.tiny)
        .padding(.horizontal, horizontalInset)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            if abs(headerHeight - newHeight) > 0.5 {
                headerHeight = newHeight
            }
        }
    }

    private var dismissButton: some View {
        Button(action: dismissSheet) {
            Image(systemName: "xmark")
                .font(.system(size: UIConstants.Size.actionIcon, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cards

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                Text("GUIDED BRIEFING")
                    .font(.system(size: UIConstants.Size.navigationChromeLabel, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                Text(heroHeadline)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(heroSupportingCopy)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: UIConstants.Spacing.small) {
                summaryChip(title: "Cards", value: report.totalCards, tint: deckColor)
                summaryChip(title: "Due", value: report.dueCards, tint: .orange)
                summaryChip(title: "Accuracy", valueText: "\(report.reviewAccuracy)%", tint: .green)
            }

            HStack(spacing: UIConstants.Spacing.small) {
                kindChip(title: "Flash", count: max(report.flashcardCards, availability.flashcardCards), tint: accentColor)
                kindChip(title: "Quiz", count: max(report.quizCards, availability.quizCards), tint: deckColor)
            }
        }
        .padding(UIConstants.Spacing.large)
        .flashcardStyle(cornerRadius: UIConstants.Radius.maximum, surfaceRole: .widget)
        .shadow(
            color: Color.teal.opacity(0.12),
            radius: UIConstants.Shadow.heavyRadius,
            y: UIConstants.Shadow.yOffset
        )
    }

    @ViewBuilder
    private var configuredSections: some View {
        switch learnSettings.grouping {
        case .readinessFirst:
            needsAttentionSection
            freshMaterialSection
            coverageSection
            stableHighlightsSection
        case .byCardKind:
            coverageSection
            needsAttentionSection
            stableHighlightsSection
            freshMaterialSection
        case .freshMaterialFirst:
            freshMaterialSection
            needsAttentionSection
            coverageSection
            stableHighlightsSection
        }
    }

    @ViewBuilder
    private var needsAttentionSection: some View {
        let insights = Array(report.focusCards.prefix(insightLimit))
        if !insights.isEmpty {
            insightSection(
                title: "Needs Attention",
                subtitle: "These are the weakest or most overdue prompts in the deck right now.",
                insights: insights
            )
        }
    }

    @ViewBuilder
    private var freshMaterialSection: some View {
        let insights = Array(report.newMaterialCards.prefix(insightLimit))
        if !insights.isEmpty {
            insightSection(
                title: "Fresh Material",
                subtitle: "New prompts to read once before you push them into active recall.",
                insights: insights
            )
        }
    }

    @ViewBuilder
    private var stableHighlightsSection: some View {
        let insights = Array(report.stableHighlights.prefix(insightLimit))
        if !insights.isEmpty {
            insightSection(
                title: "Stable Highlights",
                subtitle: "These cards look healthy enough to skim after the weaker material.",
                insights: insights
            )
        }
    }

    private var stageBreakdownCard: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            sectionTitle(
                "Study Flow",
                subtitle: "Use the deck state to decide what to read deeply, what to drill, and what only needs a skim."
            )

            HStack(alignment: .top, spacing: UIConstants.Spacing.small) {
                stageMetricCard(
                    title: "New",
                    value: report.newCards,
                    detail: "Needs first-pass reading",
                    tint: deckColor
                )
                stageMetricCard(
                    title: "Refresh",
                    value: report.dueCards,
                    detail: "Due or overdue now",
                    tint: .orange
                )
                stageMetricCard(
                    title: "Stable",
                    value: report.stableCards,
                    detail: "Likely skim-only material",
                    tint: .green
                )
            }
        }
        .padding(UIConstants.Spacing.large)
        .flashcardStyle(cornerRadius: UIConstants.Radius.large, surfaceRole: .widget)
    }

    private func insightSection(
        title: String,
        subtitle: String,
        insights: [LearnModeCardInsight]
    ) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            sectionTitle(title, subtitle: subtitle)

            ForEach(insights) { insight in
                insightRow(insight)
            }
        }
        .padding(UIConstants.Spacing.large)
        .flashcardStyle(cornerRadius: UIConstants.Radius.large, surfaceRole: .widget)
    }

    private var coverageSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            sectionTitle(
                "Deck Coverage",
                subtitle: "A quick read on how this deck distributes concepts across flashcards and quizzes."
            )

            if report.coverageGroups.isEmpty {
                Text("No coverage blocks yet. Once the deck has cards, Learn mode will group them here.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(report.coverageGroups) { group in
                    coverageRow(group)
                }
            }
        }
        .padding(UIConstants.Spacing.large)
        .flashcardStyle(cornerRadius: UIConstants.Radius.large, surfaceRole: .widget)
    }

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            ProgressView()
                .tint(deckColor)

            Text("Building the deck briefing")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Analyzing card previews and review history to group weak areas, fresh material, and stable concepts.")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(UIConstants.Spacing.large)
        .flashcardStyle(cornerRadius: UIConstants.Radius.large, surfaceRole: .widget)
    }

    private func errorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            sectionTitle(
                "Learn Report Unavailable",
                subtitle: message
            )

            Button("Try Again") {
                viewModel.load(container: context.container)
            }
            .buttonStyle(.borderedProminent)
            .tint(deckColor)
        }
        .padding(UIConstants.Spacing.large)
        .flashcardStyle(cornerRadius: UIConstants.Radius.large, surfaceRole: .widget)
    }

    // MARK: - Section Helpers

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.tiny) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summaryChip(
        title: String,
        value: Int? = nil,
        valueText: String? = nil,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

            Text(valueText ?? "\(value ?? 0)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, UIConstants.Spacing.medium)
        .padding(.vertical, UIConstants.Spacing.small)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private func kindChip(title: String, count: Int, tint: Color) -> some View {
        HStack(spacing: UIConstants.Spacing.tiny) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)

            Text("\(title) \(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, UIConstants.Spacing.medium)
        .padding(.vertical, UIConstants.Spacing.small)
        .background(Color.white.opacity(0.06), in: Capsule())
    }

    private func stageMetricCard(
        title: String,
        value: Int,
        detail: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

            Text("\(value)")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(.primary)

            Text(detail)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(UIConstants.Spacing.medium)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous))
    }

    private func insightRow(_ insight: LearnModeCardInsight) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            HStack(alignment: .top, spacing: UIConstants.Spacing.small) {
                cardKindBadge(for: insight.kind)

                Text("#\(insight.cardNumber)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            Text(insight.promptPreview)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !insight.answerPreview.isEmpty, insight.answerPreview != "Untitled" {
                Text(insight.answerPreview)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(insight.statusSummary)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(insight.recommendation)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(UIConstants.Spacing.medium)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous))
    }

    private func coverageRow(_ group: LearnModeCoverageGroup) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            HStack(alignment: .center, spacing: UIConstants.Spacing.small) {
                cardKindBadge(for: group.kind)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(group.detail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text("\(group.cardCount)")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
            }

            if !group.samplePrompts.isEmpty {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.tiny) {
                    ForEach(group.samplePrompts, id: \.self) { prompt in
                        Text("• \(prompt)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(UIConstants.Spacing.medium)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous))
    }

    private func cardKindBadge(for kind: CardKind) -> some View {
        let tint: Color
        let label: String

        switch kind {
        case .flashcard:
            tint = accentColor
            label = "FLASH"
        case .quiz:
            tint = deckColor
            label = "QUIZ"
        }

        return Text(label)
            .font(.caption2.weight(.black))
            .foregroundStyle(tint)
            .padding(.horizontal, UIConstants.Spacing.small)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14), in: Capsule())
    }

    private func dismissSheet() {
        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss()
        } else {
            dismiss()
        }
    }
}
