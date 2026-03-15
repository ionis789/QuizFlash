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
        ZStack {
            Color(uiColor: .systemGroupedBackground)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.28),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    .purple.opacity(0.18),
                    .clear
                ],
                center: .topLeading,
                startRadius: 40,
                endRadius: 420
            )

            RadialGradient(
                colors: [
                    .blue.opacity(0.14),
                    .clear
                ],
                center: .bottomTrailing,
                startRadius: 30,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
    }
}

private enum AIGenerationSheetSection: Hashable {
    case type
    case level
    case extraction
    case coverage
}

struct AIGenerationSheetView: View {
    @Bindable var viewModel: CreateDeckViewModel
    let safeAreaInsets: UIEdgeInsets
    var onPrimaryAction: () -> Void
    var onCancel: () -> Void

    @State private var expandedSection: AIGenerationSheetSection?
    @State private var selectedSourcePreview: AIGenerationSourcePreviewItem?

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

    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                    header

                    if let info = viewModel.pdfAnalysis {
                        pdfQualityBadge(info: info)
                    }

                    section(
                        .type,
                        title: "Card Type",
                        summary: viewModel.aiGenerationOptions.cardType.title,
                        subtitle: "This changes the AI prompt structure."
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
                        subtitle: "Tune depth without ambiguous short/long presets."
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
                        .extraction,
                        title: "Extraction Mode",
                        summary: viewModel.extractionMode == .fast ? "Fast" : "Quality",
                        subtitle: "Choose how the source is interpreted before generation."
                    ) {
                        VStack(spacing: UIConstants.Spacing.small) {
                            ModeButton(
                                isSelected: viewModel.extractionMode == .fast,
                                icon: "bolt.fill",
                                iconColor: .yellow,
                                title: "Fast (Free)",
                                description: viewModel.isPreparedSourcePDF
                                    ? "Uses PDF text when possible, then local OCR before Vision fallback."
                                    : "Uses local OCR text first and keeps requests lighter.",
                                onTap: { viewModel.extractionMode = .fast }
                            )
                            ModeButton(
                                isSelected: viewModel.extractionMode == .quality,
                                icon: "eye.fill",
                                iconColor: .purple,
                                title: "Quality (GPT Vision)",
                                description: viewModel.isPreparedSourcePDF
                                    ? "Sends selected PDF page ranges as page images."
                                    : "Sends selected image ranges directly to Vision.",
                                onTap: { viewModel.extractionMode = .quality }
                            )
                        }
                    }

                    section(
                        .coverage,
                        title: "Source Coverage",
                        summary: coverageSummary,
                        subtitle: "Control how the selected source is split and routed to the AI."
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
                }
                .frame(maxWidth: maxContentWidth)
                .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
                .padding(.top, safeAreaInsets.top + UIConstants.Spacing.extraLarge)
                .padding(.bottom, UIConstants.Spacing.huge)
                .frame(maxWidth: .infinity, alignment: .top)
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
            actionBar
                .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
                .padding(.top, UIConstants.Spacing.small)
                .padding(.bottom, max(safeAreaInsets.bottom, UIConstants.Spacing.large))
                .background {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(alignment: .top) {
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.12),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 1)
                        }
                }
                .opacity(selectedSourcePreview == nil ? 1 : 0)
                .allowsHitTesting(selectedSourcePreview == nil)
        }
        .fullScreenSheetDragActivationHeight(safeAreaInsets.top + 120)
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

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.92), .blue.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)

                Image(systemName: "wand.and.stars.inverse")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Generate AI Cards")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text("Saved options stay selected. Open only the section you want to change, then generate.")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: UIConstants.Spacing.small)

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
                    .background(Color.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func pdfQualityBadge(info: PDFAnalysisInfo) -> some View {
        HStack(spacing: UIConstants.Spacing.medium) {
            Image(systemName: info.qualityIcon)
                .foregroundStyle(info.isGoodForFast ? .green : .orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(info.qualityLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("\(info.pageCount) pages · ~\(info.extractedChars) chars")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(info.recommendation == .fast ? "Fast recommended" : "Quality recommended")
                .font(.caption.weight(.bold))
                .foregroundStyle(info.isGoodForFast ? .green : .orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background((info.isGoodForFast ? Color.green : Color.orange).opacity(0.14), in: Capsule())
        }
        .padding(UIConstants.Spacing.standard)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private var cardsCountCard: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HStack(alignment: .firstTextBaseline, spacing: UIConstants.Spacing.medium) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cards Count")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Used only in Auto mode to decide the total number of cards distributed across the selected source.")
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
            Text("Auto covers the entire selected source first, then scales card density by text weight so large requests stay balanced across the full material.")
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
        HStack(spacing: UIConstants.Spacing.medium) {
            Button("Cancel", action: onCancel)
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.secondary.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button(action: onPrimaryAction) {
                Text("Generate")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .disabled(!viewModel.canConfirmAIGeneration)
            .opacity(viewModel.canConfirmAIGeneration ? 1 : 0.52)
        }
        .frame(maxWidth: maxContentWidth)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Section Container

private struct ExpandableGenerationSection<Content: View>: View {
    let title: String
    let summary: String
    let subtitle: String
    let isExpanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(subtitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: UIConstants.Spacing.small)

                    HStack(spacing: UIConstants.Spacing.small) {
                        Text(summary)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.trailing)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .padding(.top, UIConstants.Spacing.medium)
                    .transition(
                        .opacity.combined(
                            with: .scale(scale: 0.98, anchor: .top)
                        )
                    )
            }
        }
        .clipped()
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
}

// MARK: - Source Preview

private struct SourcePreviewCard: View {
    let item: AIGenerationSourcePreviewItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 138, height: 98)

                    if let thumbnail = item.thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 138, height: 98)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(item.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text(item.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(item.characterCount) chars")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 138, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

private struct SourcePreviewOverlay: View {
    let image: UIImage
    let safeAreaInsets: UIEdgeInsets
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.84)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: UIConstants.Spacing.large) {
                HStack {
                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: UIConstants.isPad ? 720 : .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.24), radius: UIConstants.Shadow.heavyRadius, y: 8)

                Spacer(minLength: 0)
            }
            .padding(.top, safeAreaInsets.top + UIConstants.Spacing.standard)
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            .padding(.bottom, safeAreaInsets.bottom + UIConstants.Spacing.large)
        }
    }
}

// MARK: - Distribution Mode

private struct DistributionModeButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isSelected ? .white : .primary)

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .secondary)
                }

                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(UIConstants.Spacing.standard)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        isSelected
                            ? LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.white.opacity(0.04), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.26) : Color.white.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Manual Allocation Editor

private struct ManualAllocationCard: View {
    let title: String
    let allocation: AISourceRangeAllocation
    let upperBound: Int
    let sourceSingular: String
    let sourcePlural: String
    let cardCountUpperBound: Int
    let canRemove: Bool
    let onStartChange: (Int) -> Void
    let onEndChange: (Int) -> Void
    let onCardCountChange: (Int) -> Void
    let onRemove: () -> Void

    private var coveredItemCount: Int {
        max(allocation.endIndex - allocation.startIndex + 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)

                Spacer()

                if canRemove {
                    Button(action: onRemove) {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.red)
                            .frame(width: 30, height: 30)
                            .background(Color.red.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Source Range")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(allocation.startIndex)-\(allocation.endIndex)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .statusTextMotion(trigger: "\(allocation.startIndex)-\(allocation.endIndex)")
                }

                Text("Covers \(coveredItemCount) \(coveredItemCount == 1 ? sourceSingular : sourcePlural)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                DiscreteRangeSlider(
                    lowerValue: allocation.startIndex,
                    upperValue: allocation.endIndex,
                    range: 1...max(upperBound, 1),
                    onLowerChange: onStartChange,
                    onUpperChange: onEndChange
                )

                HStack {
                    Text("1")
                    Spacer()
                    Text("\(max(upperBound, 1))")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Cards")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(allocation.cardCount)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .statusTextMotion(trigger: allocation.cardCount)
                }

                DiscreteValueSlider(
                    value: allocation.cardCount,
                    range: 1...max(cardCountUpperBound, 1),
                    onChange: onCardCountChange
                )

                HStack {
                    Text("1")
                    Spacer()
                    Text("\(max(cardCountUpperBound, 1))")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            }
        }
        .padding(UIConstants.Spacing.standard)
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

// MARK: - Controls

/// A minimalist discrete slider for integer-backed generation controls.
private struct DiscreteValueSlider: View {
    let value: Int
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void

    private let thumbSize = CGFloat(28)
    private let trackHeight = CGFloat(8)

    var body: some View {
        GeometryReader { proxy in
            let metrics = SliderMetrics(width: proxy.size.width, thumbSize: thumbSize)
            let thumbOffset = metrics.offset(for: value, in: range)
            let filledWidth = thumbOffset + (thumbSize / 2)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.95), .blue.opacity(0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: filledWidth, height: trackHeight)

                SliderThumb()
                    .offset(x: thumbOffset)
            }
            .frame(height: thumbSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let snappedValue = metrics.snappedValue(
                            for: gesture.location.x,
                            in: range
                        )
                        if snappedValue != value {
                            onChange(snappedValue)
                        }
                    }
            )
        }
        .frame(height: thumbSize)
    }
}

/// A dual-handle discrete slider used to select image or page ranges.
private struct DiscreteRangeSlider: View {
    let lowerValue: Int
    let upperValue: Int
    let range: ClosedRange<Int>
    let onLowerChange: (Int) -> Void
    let onUpperChange: (Int) -> Void

    @State private var activeHandle: RangeHandle?

    private let thumbSize = CGFloat(28)
    private let trackHeight = CGFloat(8)

    var body: some View {
        GeometryReader { proxy in
            let metrics = SliderMetrics(width: proxy.size.width, thumbSize: thumbSize)
            let lowerOffset = metrics.offset(for: lowerValue, in: range)
            let upperOffset = metrics.offset(for: upperValue, in: range)
            let lowerCenter = lowerOffset + (thumbSize / 2)
            let upperCenter = upperOffset + (thumbSize / 2)
            let selectedWidth = max(upperCenter - lowerCenter, trackHeight)
            let selectedOffset = upperCenter == lowerCenter
                ? max(lowerCenter - (trackHeight / 2), 0)
                : lowerCenter

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.92), .blue.opacity(0.86)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: selectedWidth,
                        height: trackHeight
                    )
                    .offset(x: selectedOffset)

                SliderThumb(isActive: activeHandle == .lower)
                    .offset(x: lowerOffset)

                SliderThumb(isActive: activeHandle == .upper)
                    .offset(x: upperOffset)
            }
            .frame(height: thumbSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let handle = activeHandle
                            ?? preferredHandle(for: gesture.location.x, metrics: metrics)
                        activeHandle = handle

                        let snappedValue = metrics.snappedValue(
                            for: gesture.location.x,
                            in: range
                        )

                        switch handle {
                        case .lower:
                            onLowerChange(min(snappedValue, upperValue))
                        case .upper:
                            onUpperChange(max(snappedValue, lowerValue))
                        }
                    }
                    .onEnded { _ in
                        activeHandle = nil
                    }
            )
        }
        .frame(height: thumbSize)
    }

    private func preferredHandle(
        for locationX: CGFloat,
        metrics: SliderMetrics
    ) -> RangeHandle {
        let lowerCenter = metrics.offset(for: lowerValue, in: range) + (thumbSize / 2)
        let upperCenter = metrics.offset(for: upperValue, in: range) + (thumbSize / 2)

        if abs(lowerCenter - upperCenter) < 0.5 {
            return locationX >= lowerCenter ? .upper : .lower
        }

        return abs(locationX - lowerCenter) <= abs(locationX - upperCenter) ? .lower : .upper
    }
}

private enum RangeHandle {
    case lower
    case upper
}

/// Layout helper for discrete slider snapping and thumb positioning.
private struct SliderMetrics {
    let width: CGFloat
    let thumbSize: CGFloat

    private var usableWidth: CGFloat {
        max(width - thumbSize, 1)
    }

    func offset(for value: Int, in range: ClosedRange<Int>) -> CGFloat {
        let clampedValue = min(max(value, range.lowerBound), range.upperBound)
        guard range.lowerBound != range.upperBound else { return 0 }

        let progress = CGFloat(clampedValue - range.lowerBound)
            / CGFloat(range.upperBound - range.lowerBound)
        return progress * usableWidth
    }

    func snappedValue(for locationX: CGFloat, in range: ClosedRange<Int>) -> Int {
        guard range.lowerBound != range.upperBound else { return range.lowerBound }

        let clampedX = min(max(locationX - (thumbSize / 2), 0), usableWidth)
        let progress = clampedX / usableWidth
        let rawValue = CGFloat(range.lowerBound)
            + progress * CGFloat(range.upperBound - range.lowerBound)
        return Int(rawValue.rounded())
    }
}

private struct SliderThumb: View {
    var isActive = false

    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 28, height: 28)
            .overlay {
                Circle()
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(isActive ? 0.24 : 0.18), radius: isActive ? 8 : 5, y: 3)
            .scaleEffect(isActive ? 1.06 : 1)
            .animation(.easeInOut(duration: UIConstants.Animation.instant), value: isActive)
    }
}

private struct SheetValueStepper: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: UIConstants.Spacing.standard) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)

            Spacer(minLength: UIConstants.Spacing.small)

            HStack(spacing: UIConstants.Spacing.small) {
                StepperButton(symbol: "minus") {
                    onChange(max(value - 1, range.lowerBound))
                }
                .disabled(value <= range.lowerBound)

                Text("\(value)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .frame(minWidth: 34)
                    .statusTextMotion(trigger: value)

                StepperButton(symbol: "plus") {
                    onChange(min(value + 1, range.upperBound))
                }
                .disabled(value >= range.upperBound)
            }
        }
        .padding(.horizontal, UIConstants.Spacing.standard)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

private struct StepperButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct GenerationChoiceCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .secondary)
                }

                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : .primary)

                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
            .padding(UIConstants.Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        isSelected
                            ? LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.white.opacity(0.04), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.28) : Color.white.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct GenerationRowButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: UIConstants.Spacing.medium) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.03))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.32) : Color.white.opacity(0.05), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ModeButton: View {
    let isSelected: Bool
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.title3)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .font(.title3)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }
}
