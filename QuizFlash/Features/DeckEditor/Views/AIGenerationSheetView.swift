//
//  AIGenerationSheetView.swift
//  QuizFlash
//
//  Compact AI generation configuration sheet with source-aware coverage planning.
//

import SwiftUI

// MARK: - AI Generation Sheet

struct AIGenerationSheetBackground: View {
    var body: some View {
        StandardSheetTopStripBackground()
            .ignoresSafeArea()
    }
}

private enum AIGenerationSheetSection: Hashable {
    case type
    case level
    case language
    case extraction
    case coverage
}

struct AIGenerationSheetView: View {
    @Bindable var viewModel: DeckWorkspaceViewModel
    let safeAreaInsets: UIEdgeInsets
    var onPrimaryAction: () -> Void
    var onCancel: () -> Void

    @State private var expandedSection: AIGenerationSheetSection? = .coverage
    @State private var selectedSourcePreview: AIGenerationSourcePreviewItem?

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    private var maxContentWidth: CGFloat {
        UIConstants.isPad ? 760 : .infinity
    }

    private var sourceNounPlural: String {
        viewModel.isPreparedSourcePDF ? "pages" : "images"
    }

    private var sourceNounSingular: String {
        viewModel.isPreparedSourcePDF ? "page" : "image"
    }

    private var sourceCountSummary: String {
        "\(viewModel.preparedAISource?.itemCount ?? 0) \(sourceNounPlural)"
    }

    private var isPreparingSource: Bool {
        viewModel.isPreparingAISource && viewModel.preparedAISource == nil
    }

    var body: some View {
        ZStack {
            Group {
                if isPreparingSource {
                    preparingLayout
                        .transition(.opacity)
                } else {
                    configurationLayout
                        .transition(.opacity)
                }
            }

            if let preview = selectedSourcePreview,
               let image = previewImage(for: preview) {
                SourcePreviewOverlay(
                    image: image,
                    safeAreaInsets: safeAreaInsets,
                    onClose: {
                        withAnimation(.easeInOut(duration: UIConstants.Animation.standard)) {
                            selectedSourcePreview = nil
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isPreparingSource {
                actionBar
                    .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
                    .padding(.top, UIConstants.Spacing.small)
                    .padding(.bottom, max(safeAreaInsets.bottom, UIConstants.Spacing.large))
                    .background {
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.22),
                                Color.clear
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                        .ignoresSafeArea()
                    }
                    .opacity(selectedSourcePreview == nil ? 1 : 0)
                    .allowsHitTesting(selectedSourcePreview == nil)
            }
        }
        .task(id: isPreparingSource) {
            guard isPreparingSource else { return }
            viewModel.startPendingAISourcePreparationIfNeeded()
        }
        .fullScreenSheetDragActivationHeight(safeAreaInsets.top + 120)
    }

    private var configurationLayout: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                topBar

                sourceStatusCard
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))

                section(
                    .coverage,
                    title: "Source Coverage",
                    summary: coverageSummary,
                    subtitle: "Range planning"
                ) {
                    sourcePreviewStrip
                    distributionModePicker

                    if viewModel.aiGenerationOptions.sourceDistributionMode == .auto {
                        cardsCountCard
                        autoCoverageSummary
                    } else {
                        manualCoverageEditor
                    }
                }

                section(
                    .type,
                    title: "Card Type",
                    summary: viewModel.aiGenerationOptions.cardType.title,
                    subtitle: "Prompt format"
                ) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: UIConstants.Spacing.small) {
                        ForEach(AICardGenerationType.allCases) { type in
                            GenerationChoiceCard(
                                title: type.title,
                                subtitle: type.subtitle,
                                icon: type.systemImage,
                                isSelected: viewModel.aiGenerationOptions.cardType == type
                            ) {
                                viewModel.aiGenerationOptions.cardType = type
                            }
                        }
                    }
                }

                section(
                    .level,
                    title: "Card Level",
                    summary: viewModel.aiGenerationOptions.cardLevel.title,
                    subtitle: "Depth"
                ) {
                    VStack(spacing: UIConstants.Spacing.small) {
                        ForEach(AICardGenerationLevel.allCases) { level in
                            GenerationRowButton(
                                title: level.title,
                                subtitle: level.subtitle,
                                isSelected: viewModel.aiGenerationOptions.cardLevel == level
                            ) {
                                viewModel.aiGenerationOptions.cardLevel = level
                            }
                        }
                    }
                }

                section(
                    .language,
                    title: "Output Language",
                    summary: viewModel.aiGenerationOptions.outputLanguageSummary,
                    subtitle: "Auto detect or force a language"
                ) {
                    outputLanguagePicker
                }

                section(
                    .extraction,
                    title: "Extraction Mode",
                    summary: viewModel.extractionMode == .fast ? "Fast" : "Quality",
                    subtitle: "Speed vs quality"
                ) {
                    VStack(spacing: UIConstants.Spacing.small) {
                        ModeButton(
                            isSelected: viewModel.extractionMode == .fast,
                            icon: "bolt.fill",
                            iconColor: .yellow,
                            title: "Fast",
                            description: viewModel.isPreparedSourcePDF
                                ? "Uses embedded text first, then local OCR when needed."
                                : "Starts from local OCR text and keeps requests lighter.",
                            onTap: { viewModel.extractionMode = .fast }
                        )
                        ModeButton(
                            isSelected: viewModel.extractionMode == .quality,
                            icon: "eye.fill",
                            iconColor: .purple,
                            title: "Quality",
                            description: viewModel.isPreparedSourcePDF
                                ? "Sends selected pages as rendered images to Vision."
                                : "Sends selected images directly to Vision.",
                            onTap: { viewModel.extractionMode = .quality }
                        )
                    }
                }

            }
            .frame(maxWidth: maxContentWidth)
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            .padding(.top, safeAreaInsets.top + UIConstants.Spacing.small)
            .padding(.bottom, UIConstants.Spacing.huge)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var preparingLayout: some View {
        VStack(spacing: 0) {
            topBar
                .frame(maxWidth: maxContentWidth)
                .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
                .padding(.top, safeAreaInsets.top + UIConstants.Spacing.small)

            Spacer(minLength: UIConstants.Spacing.large)

            SourcePreparationCenterStage(state: viewModel.aiSourcePreparationState)
                .frame(maxWidth: 420)
                .padding(.horizontal, UIConstants.Layout.screenEdgeInset)

            Spacer(minLength: UIConstants.Spacing.huge)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var coverageSummary: String {
        switch viewModel.aiGenerationOptions.sourceDistributionMode {
        case .auto:
            return "Auto · \(viewModel.requestedCardCount) cards · \(sourceCountSummary)"
        case .manual:
            let ranges = viewModel.manualAISourceAllocations.count
            let totalCards = viewModel.manualAllocatedCardCount
            return "Manual · \(totalCards) cards · \(ranges) range\(ranges == 1 ? "" : "s")"
        }
    }

    private var topBar: some View {
        HStack {
            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var sourceStatusCard: some View {
        if let source = viewModel.preparedAISource {
            HStack(spacing: UIConstants.Spacing.medium) {
                ZStack {
                    Circle()
                        .fill((viewModel.pdfAnalysis?.isGoodForFast == false ? Color.orange : Color.green).opacity(0.16))
                        .frame(width: 42, height: 42)

                    Image(systemName: viewModel.pdfAnalysis?.qualityIcon ?? "checkmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(viewModel.pdfAnalysis?.isGoodForFast == false ? .orange : .green)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(sourceStatusTitle)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(sourceStatusSubtitle(source: source))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: UIConstants.Spacing.small)

                if let badge = sourceRecommendationBadge {
                    Text(badge.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(badge.tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(badge.tint.opacity(0.14), in: Capsule())
                }
            }
            .padding(UIConstants.Spacing.large)
            .flashcardStyle(cornerRadius: 28, surfaceRole: .widget)
        }
    }

    private var cardsCountCard: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HStack(alignment: .firstTextBaseline, spacing: UIConstants.Spacing.medium) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cards Count")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Total cards for auto distribution.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: UIConstants.Spacing.small)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(viewModel.requestedCardCount)")
                        .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                        .statusTextMotion(trigger: viewModel.requestedCardCount)

                    Text("cards")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
            }

            VStack(spacing: UIConstants.Spacing.small) {
                DiscreteValueSlider(
                    value: viewModel.requestedCardCount,
                    range: 1...100
                ) { newValue in
                    viewModel.setRequestedCardCount(newValue)
                }

                HStack {
                    Text("1")
                    Spacer()
                    Text("100")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            }
        }
        .padding(UIConstants.Spacing.large)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        _ section: AIGenerationSheetSection,
        title: String,
        summary: String,
        subtitle: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        ExpandableGenerationSection(
            title: title,
            summary: summary,
            subtitle: subtitle,
            isExpanded: expandedSection == section,
            onToggle: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    expandedSection = expandedSection == section ? nil : section
                }
            },
            content: content
        )
    }

    @ViewBuilder
    private var sourcePreviewStrip: some View {
        if let source = viewModel.preparedAISource {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                HStack {
                    Text("Selected source")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(source.itemCount) \(sourceNounPlural) · \(source.totalCharacterCount) chars")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: UIConstants.Spacing.small) {
                        ForEach(source.previewItems) { item in
                            SourcePreviewCard(item: item) {
                                guard previewImage(for: item) != nil else { return }
                                withAnimation(.easeInOut(duration: UIConstants.Animation.standard)) {
                                    selectedSourcePreview = item
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func previewImage(for item: AIGenerationSourcePreviewItem) -> UIImage? {
        guard let source = viewModel.preparedAISource else { return item.thumbnail }

        if source.isPDF {
            return item.thumbnail
        }

        let sourceIndex = item.index - 1
        guard source.images.indices.contains(sourceIndex) else {
            return item.thumbnail
        }
        return source.images[sourceIndex]
    }

    private var distributionModePicker: some View {
        VStack(spacing: UIConstants.Spacing.small) {
            HStack(spacing: UIConstants.Spacing.small) {
                DistributionModeButton(
                    title: "Auto",
                    subtitle: "Spread cards by detected text density.",
                    isSelected: viewModel.aiGenerationOptions.sourceDistributionMode == .auto
                ) {
                    viewModel.setSourceDistributionMode(.auto)
                }

                DistributionModeButton(
                    title: "Manual",
                    subtitle: "Assign exact ranges and card counts.",
                    isSelected: viewModel.aiGenerationOptions.sourceDistributionMode == .manual
                ) {
                    viewModel.setSourceDistributionMode(.manual)
                }
            }
        }
    }

    private var outputLanguagePicker: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            HStack(spacing: UIConstants.Spacing.small) {
                DistributionModeButton(
                    title: "Auto",
                    subtitle: "Detect from source text.",
                    isSelected: viewModel.aiGenerationOptions.outputLanguageMode == .auto
                ) {
                    viewModel.aiGenerationOptions.outputLanguageMode = .auto
                }

                DistributionModeButton(
                    title: "Manual",
                    subtitle: "Force one language for all cards.",
                    isSelected: viewModel.aiGenerationOptions.outputLanguageMode == .manual
                ) {
                    viewModel.aiGenerationOptions.outputLanguageMode = .manual
                    if viewModel.aiGenerationOptions.manualOutputLanguage == nil {
                        viewModel.aiGenerationOptions.manualOutputLanguage = AIGenerationLanguageHint.supportedOutputLanguages.first
                    }
                }
            }

            if viewModel.aiGenerationOptions.outputLanguageMode == .manual {
                Menu {
                    ForEach(AIGenerationLanguageHint.supportedOutputLanguages, id: \.languageCode) { language in
                        Button {
                            viewModel.aiGenerationOptions.manualOutputLanguage = language
                        } label: {
                            if viewModel.aiGenerationOptions.manualOutputLanguage?.languageCode == language.languageCode {
                                Label(language.displayName, systemImage: "checkmark")
                            } else {
                                Text(language.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: UIConstants.Spacing.small) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Selected language")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)

                            Text(viewModel.aiGenerationOptions.manualOutputLanguage?.displayName ?? "Choose a language")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: UIConstants.Spacing.small)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, UIConstants.Spacing.standard)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Label("AI detects the source language once and keeps the whole run in that language.", systemImage: "waveform.and.magnifyingglass")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var autoCoverageSummary: some View {
        let allocations = viewModel.summarizedAISourceAllocations
        let itemCount = viewModel.preparedAISource?.itemCount ?? 0
        let coverageColumns = UIConstants.isPad
            ? [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
        let sourceCoverageTitle: String = {
            guard itemCount > 0 else { return "Source coverage" }
            if itemCount == 1 {
                return "\(sourceNounSingular.capitalized) 1 covered"
            }
            return "\(sourceNounPlural.capitalized) 1-\(itemCount) covered"
        }()
        let estimatedRequests = allocations.reduce(into: 0) { partialResult, allocation in
            let batchSize = viewModel.aiGenerationOptions.resolvedCardsPerBatch(for: allocation.cardCount)
            partialResult += Int(ceil(Double(allocation.cardCount) / Double(max(batchSize, 1))))
        }

        return VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            Text("Auto keeps the full source covered, then balances density by text weight.")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: coverageColumns, spacing: UIConstants.Spacing.small) {
                coveragePill(
                    title: sourceCoverageTitle,
                    subtitle: "Full coverage"
                )

                coveragePill(
                    title: "\(allocations.count) range\(allocations.count == 1 ? "" : "s")",
                    subtitle: "Coverage plan"
                )

                coveragePill(
                    title: "\(estimatedRequests) AI request\(estimatedRequests == 1 ? "" : "s")",
                    subtitle: "Adaptive delivery"
                )
            }

            VStack(spacing: UIConstants.Spacing.small) {
                ForEach(allocations) { allocation in
                    HStack(spacing: UIConstants.Spacing.standard) {
                        Text(viewModel.allocationTitle(for: allocation))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer(minLength: UIConstants.Spacing.small)

                        Text("\(allocation.cardCount) card\(allocation.cardCount == 1 ? "" : "s")")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.05), in: Capsule())
                    }
                    .padding(.horizontal, UIConstants.Spacing.standard)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    }
                }
            }
        }
    }

    private func coveragePill(
        title: String,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(subtitle)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private var manualCoverageEditor: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            ForEach(viewModel.manualAISourceAllocations) { allocation in
                ManualAllocationCard(
                    title: viewModel.allocationTitle(for: allocation),
                    allocation: allocation,
                    upperBound: max(viewModel.preparedAISource?.itemCount ?? 1, 1),
                    sourceSingular: sourceNounSingular,
                    sourcePlural: sourceNounPlural,
                    cardCountUpperBound: 100,
                    canRemove: viewModel.manualAISourceAllocations.count > 1,
                    onStartChange: { viewModel.updateManualAllocation(id: allocation.id, startIndex: $0) },
                    onEndChange: { viewModel.updateManualAllocation(id: allocation.id, endIndex: $0) },
                    onCardCountChange: { viewModel.updateManualAllocation(id: allocation.id, cardCount: $0) },
                    onRemove: { viewModel.removeManualAllocation(id: allocation.id) }
                )
            }

            Button {
                viewModel.addManualAllocation()
            } label: {
                Label("Add Range", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            if let message = viewModel.manualAllocationValidationMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Manual ranges currently generate \(viewModel.manualAllocatedCardCount) cards.", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        HStack(spacing: UIConstants.Spacing.small) {
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.plain)

            Button(action: onPrimaryAction) {
                Text("Generate")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(accent, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canConfirmAIGeneration)
            .opacity(viewModel.canConfirmAIGeneration ? 1 : 0.48)
        }
        .frame(maxWidth: maxContentWidth)
        .frame(maxWidth: .infinity)
    }

    private var sourceStatusTitle: String {
        if let info = viewModel.pdfAnalysis {
            return info.qualityLabel
        }
        return viewModel.isPreparedSourcePDF ? "Document ready" : "Images ready"
    }

    private func sourceStatusSubtitle(source: AIPreparedGenerationSource) -> String {
        if let info = viewModel.pdfAnalysis {
            return "\(info.pageCount) pages · ~\(info.extractedChars) chars"
        }
        return "\(source.itemCount) \(sourceNounPlural) · \(source.totalCharacterCount) chars"
    }

    private var sourceRecommendationBadge: (title: String, tint: Color)? {
        guard let info = viewModel.pdfAnalysis else { return nil }
        return (
            info.recommendation == .fast ? "Fast" : "Quality",
            info.isGoodForFast ? .green : .orange
        )
    }
}
