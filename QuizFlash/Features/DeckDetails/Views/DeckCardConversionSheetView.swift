//
//  DeckCardConversionSheetView.swift
//  QuizFlash
//
//  Deck-scoped AI conversion flow for converting cards between mixed card kinds.
//

import SwiftData
import SwiftUI

// MARK: - Deck Card Conversion Sheet

struct DeckCardConversionSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var context

    @Bindable var viewModel: DeckViewModel
    let deck: DeckModel
    let safeAreaInsets: UIEdgeInsets
    var onDismiss: () -> Void
    var onOpenDestinationDeck: ((PersistentIdentifier) -> Void)? = nil

    @State private var headerHeight: CGFloat = 0

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    private var deckColor: Color {
        Color(hex: deck.colorHex) ?? accent
    }

    private var horizontalInset: CGFloat {
        horizontalSizeClass == .compact
            ? UIConstants.Layout.compactScreenEdgeInset
            : UIConstants.Layout.screenEdgeInset
    }

    var body: some View {
        GeometryReader { geo in
            let resolvedSafeTopInset = max(safeAreaInsets.top, geo.safeAreaInsets.top)
            let resolvedSafeBottomInset = max(safeAreaInsets.bottom, geo.safeAreaInsets.bottom)

            ZStack(alignment: .top) {
                CardPreviewModeBackground()
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                        if let progress = viewModel.conversionProgress {
                            progressContent(progress)
                        } else if let summary = viewModel.conversionSummary {
                            summaryContent(summary)
                        } else if let request = viewModel.conversionRequest {
                            configurationContent(request)
                        }

                        if let errorMessage = viewModel.conversionErrorMessage,
                           viewModel.conversionProgress == nil {
                            errorCard(errorMessage)
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
    }

    private func header(safeTopInset: CGFloat) -> some View {
        VStack(spacing: UIConstants.Spacing.small) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 56, height: 5)
                .accessibilityHidden(true)

            ZStack {
                VStack(spacing: 2) {
                    Text("Convert Cards")
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
                .glassButton(shape: .circle)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func configurationContent(_ request: DeckCardConversionRequest) -> some View {
        overviewCard(request)
        scopeCard(request)
        targetKindCard(request)
        destinationCard(request)
        actionCard(request)
    }

    private func overviewCard(_ request: DeckCardConversionRequest) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
                ZStack {
                    RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                        .fill(deckColor.opacity(0.14))
                        .frame(width: 72, height: 72)

                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(deckColor)
                }

                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    Text("AI CONVERSION")
                        .font(.system(size: UIConstants.Size.navigationChromeLabel, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text("Convert this deck into \(request.targetKind.displayTitle) cards")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Original cards always stay intact. Same-deck runs append converted copies with lineage metadata.")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: UIConstants.Spacing.small) {
                statusChip(
                    title: "\(request.sourceCount) source card\(request.sourceCount == 1 ? "" : "s")",
                    icon: "rectangle.stack.fill",
                    tint: deckColor
                )

                statusChip(
                    title: request.destination.title,
                    icon: request.destination == .sameDeck ? "square.stack.3d.up.fill" : "square.on.square.fill",
                    tint: accent
                )
            }
        }
        .padding(UIConstants.Spacing.large)
        .widgetStyle(cornerRadius: UIConstants.Radius.maximum)
    }

    private func scopeCard(_ request: DeckCardConversionRequest) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            sectionHeader(title: "Scope", subtitle: "Choose which cards to convert")

            VStack(spacing: UIConstants.Spacing.small) {
                ForEach(request.availableScopes) { scope in
                    selectionRow(
                        title: scope.title,
                        subtitle: scopeSummary(for: scope, request: request),
                        icon: scopeIcon(for: scope),
                        isSelected: request.scope == scope
                    ) {
                        updateRequest { draft in
                            draft.scope = scope
                        }
                    }
                }
            }
        }
        .padding(UIConstants.Spacing.large)
        .widgetStyle(cornerRadius: UIConstants.Radius.large)
    }

    private func targetKindCard(_ request: DeckCardConversionRequest) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            sectionHeader(title: "Target Type", subtitle: "Pick the output card format")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: UIConstants.Spacing.small) {
                ForEach(CardKind.allCases, id: \.self) { kind in
                    kindButton(kind, isSelected: request.targetKind == kind)
                }
            }

            Text("Cards already in \(request.targetKind.displayTitle) format are skipped automatically.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(UIConstants.Spacing.large)
        .widgetStyle(cornerRadius: UIConstants.Radius.large)
    }

    private func destinationCard(_ request: DeckCardConversionRequest) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            sectionHeader(title: "Destination", subtitle: "Choose where converted cards should land")

            VStack(spacing: UIConstants.Spacing.small) {
                ForEach(DeckCardConversionDestinationOption.allCases) { option in
                    selectionRow(
                        title: option.title,
                        subtitle: option.subtitle,
                        icon: option == .sameDeck ? "square.stack.3d.up.fill" : "square.on.square.fill",
                        isSelected: request.destination == option
                    ) {
                        updateRequest { draft in
                            draft.destination = option
                        }
                    }
                }
            }

            if request.destination == .newDeck {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    Text("New Deck Title")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    TextField("Converted deck title", text: Binding(
                        get: { viewModel.conversionRequest?.newDeckTitle ?? "" },
                        set: { newValue in
                            updateRequest { draft in
                                draft.newDeckTitle = newValue
                            }
                        }
                    ))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.75)
                    }

                    Text("The new deck copies the current deck's icon, color, folder, and grouping preference, but starts with fresh review history.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(UIConstants.Spacing.large)
        .widgetStyle(cornerRadius: UIConstants.Radius.large)
    }

    private func actionCard(_ request: DeckCardConversionRequest) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            sectionHeader(title: "Run", subtitle: "The conversion runs in recoverable AI batches")

            Text("If a batch fails, QuizFlash retries those cards individually so the run can still finish with created, skipped, and failed counts.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                viewModel.startConversion(for: deck, context: context)
            } label: {
                HStack(spacing: UIConstants.Spacing.small) {
                    Image(systemName: "sparkles")
                    Text("Start Conversion")
                }
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: [deckColor, accent],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(!request.canStart)
            .opacity(request.canStart ? 1 : 0.55)
        }
        .padding(UIConstants.Spacing.large)
        .widgetStyle(cornerRadius: UIConstants.Radius.large)
    }

    private func progressContent(_ progress: DeckCardConversionProgress) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            sectionHeader(title: "Converting", subtitle: progress.statusMessage)

            VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                ProgressView(value: progress.fractionCompleted)
                    .tint(deckColor)

                Text("\(progress.completedCount) / \(progress.totalCount) processed")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)

                HStack(spacing: UIConstants.Spacing.small) {
                    metricChip("Created \(progress.createdCount)", tint: .green)
                    metricChip("Skipped \(progress.skippedCount)", tint: .orange)
                    metricChip("Failed \(progress.failedCount)", tint: .red)
                }
            }
        }
        .padding(UIConstants.Spacing.large)
        .widgetStyle(cornerRadius: UIConstants.Radius.maximum)
    }

    private func summaryContent(_ summary: DeckCardConversionSummary) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            sectionHeader(
                title: "Conversion Complete",
                subtitle: "\(summary.createdCount) \(summary.targetKind.displayTitle.lowercased()) card\(summary.createdCount == 1 ? "" : "s") created"
            )

            HStack(spacing: UIConstants.Spacing.small) {
                metricChip("Created \(summary.createdCount)", tint: .green)
                metricChip("Skipped \(summary.skippedCount)", tint: .orange)
                metricChip("Failed \(summary.failedCount)", tint: .red)
            }

            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                Text("Destination")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Text(summary.destinationDeckTitle)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)

                Text(summary.destination == .sameDeck
                     ? "Original cards stayed in place and the converted copies were appended to the same deck."
                     : "A new sibling deck was created with the converted results only.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: UIConstants.Spacing.small) {
                if summary.destination == .newDeck,
                   let destinationDeckID = summary.destinationDeckID,
                   let onOpenDestinationDeck {
                    Button {
                        onOpenDestinationDeck(destinationDeckID)
                    } label: {
                        HStack(spacing: UIConstants.Spacing.small) {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Open Converted Deck")
                        }
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(deckColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button("Done", action: dismissSheet)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .buttonStyle(.plain)
                } else {
                    Button("Done", action: dismissSheet)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(deckColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(UIConstants.Spacing.large)
        .widgetStyle(cornerRadius: UIConstants.Radius.maximum)
    }

    private func errorCard(_ errorMessage: String) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            sectionHeader(title: "Conversion Error", subtitle: "The run stopped before it could finish")

            Text(errorMessage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(UIConstants.Spacing.large)
        .widgetStyle(cornerRadius: UIConstants.Radius.large)
        .overlay {
            RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                .stroke(Color.red.opacity(0.22), lineWidth: 1)
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusChip(title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private func metricChip(_ title: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private func selectionRow(
        title: String,
        subtitle: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: UIConstants.Spacing.medium) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill((isSelected ? deckColor : Color.white).opacity(isSelected ? 0.16 : 0.05))
                        .frame(width: 46, height: 46)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isSelected ? deckColor : .secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isSelected ? deckColor : .secondary)
            }
            .padding(14)
            .background(Color.white.opacity(isSelected ? 0.08 : 0.03), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func kindButton(_ kind: CardKind, isSelected: Bool) -> some View {
        Button {
            updateRequest { draft in
                draft.targetKind = kind
            }
        } label: {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                Image(systemName: kind.conversionSystemImage)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(isSelected ? deckColor : .secondary)

                Text(kind.displayTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(kindTargetSubtitle(kind))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .padding(14)
            .background(Color.white.opacity(isSelected ? 0.08 : 0.03), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isSelected ? deckColor.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func kindTargetSubtitle(_ kind: CardKind) -> String {
        switch kind {
        case .flashcard:
            return "Question and answer zones."
        case .match:
            return "Short prompt-answer pairs."
        case .quiz:
            return "Multiple-choice checks."
        case .write:
            return "Typed blank-recall prompts."
        }
    }

    private func scopeSummary(
        for scope: DeckCardConversionScopeOption,
        request: DeckCardConversionRequest
    ) -> String {
        switch scope {
        case .wholeDeck:
            return "\(request.wholeDeckCardCount) card\(request.wholeDeckCardCount == 1 ? "" : "s") in the current deck"
        case .recommendedCards:
            let count = request.recommendedCardCount
            return "\(count) readiness-flagged card\(count == 1 ? "" : "s")"
        case .selectedCards:
            let count = request.selectedCardCount
            return "\(count) currently selected card\(count == 1 ? "" : "s")"
        case .singleCard:
            return "Convert the one card opened from the action menu"
        }
    }

    private func scopeIcon(for scope: DeckCardConversionScopeOption) -> String {
        switch scope {
        case .wholeDeck:
            return "square.stack.3d.up.fill"
        case .recommendedCards:
            return "wand.and.stars"
        case .selectedCards:
            return "checkmark.circle.fill"
        case .singleCard:
            return "rectangle.fill.on.rectangle.angled.fill"
        }
    }

    private func updateRequest(_ mutate: (inout DeckCardConversionRequest) -> Void) {
        guard var request = viewModel.conversionRequest else { return }
        mutate(&request)
        viewModel.conversionRequest = request
    }

    private func dismissSheet() {
        onDismiss()
        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss()
        } else {
            dismiss()
        }
    }
}
