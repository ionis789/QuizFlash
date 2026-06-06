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
        Color.black
            .ignoresSafeArea()
    }
}

struct AIGenerationSheetView: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Bindable var viewModel: DeckWorkspaceViewModel
    let safeAreaInsets: UIEdgeInsets
    var onPrimaryAction: () -> Void
    var onCancel: () -> Void

    @State private var selectedSourcePreview: AIGenerationSourcePreviewItem?
    @State private var selectedSourcePreviewImage: UIImage?
    @State private var sourcePreviewTask: Task<Void, Never>?
    @State private var headerHeight: CGFloat = 0

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    private var maxContentWidth: CGFloat {
        UIConstants.isPad ? 760 : .infinity
    }

    private var sourceNounPlural: String {
        viewModel.isPreparedSourcePDF
            ? AppLocalization.string("pages", locale: appPreferences.resolvedLocale)
            : AppLocalization.string("images", locale: appPreferences.resolvedLocale)
    }

    private var sourceNounSingular: String {
        viewModel.isPreparedSourcePDF
            ? AppLocalization.string("page", locale: appPreferences.resolvedLocale)
            : AppLocalization.string("image", locale: appPreferences.resolvedLocale)
    }

    private var isPreparingSource: Bool {
        viewModel.isPreparingAISource && viewModel.preparedAISource == nil
    }

    var body: some View {
        GeometryReader { proxy in
            let resolvedSafeTopInset = max(safeAreaInsets.top, proxy.safeAreaInsets.top)
            let resolvedSafeBottomInset = max(safeAreaInsets.bottom, proxy.safeAreaInsets.bottom)

            ZStack(alignment: .top) {
                if isPreparingSource {
                    preparingLayout
                        .transition(.opacity)
                } else {
                    configurationLayout(bottomClearance: bottomActionClearance(safeBottomInset: resolvedSafeBottomInset))
                        .transition(.opacity)
                }

                header(safeTopInset: resolvedSafeTopInset)
                    .zIndex(2)

                if selectedSourcePreview != nil {
                    SourcePreviewOverlay(
                        image: selectedSourcePreviewImage,
                        safeAreaInsets: safeAreaInsets,
                        onClose: closeSourcePreview
                    )
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if !isPreparingSource {
                    bottomActionChrome(safeBottomInset: resolvedSafeBottomInset)
                        .opacity(selectedSourcePreview == nil ? 1 : 0)
                        .allowsHitTesting(selectedSourcePreview == nil)
                }
            }
        }
        .task(id: isPreparingSource) {
            guard isPreparingSource else { return }
            viewModel.startPendingAISourcePreparationIfNeeded()
        }
    }

    private func configurationLayout(bottomClearance: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                section(
                    title: "Card Type",
                    summary: generationSettingsSummary
                ) {
                    generationSettingsContent
                }

                section(
                    title: "Source Coverage",
                    summary: coverageSummary
                ) {
                    sourceCoverageContent
                }

            }
            .frame(maxWidth: maxContentWidth)
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            .padding(.top, headerHeight + UIConstants.Spacing.large)
            .padding(.bottom, bottomClearance)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var preparingLayout: some View {
        VStack(spacing: 0) {
            Spacer(minLength: headerHeight + UIConstants.Spacing.large)

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
            return "Auto · \(viewModel.requestedCardCount) cards"
        case .manual:
            let totalCards = viewModel.manualAllocatedCardCount
            return "Manual · \(totalCards) cards"
        }
    }

    private var generationSettingsSummary: String {
        [
            viewModel.aiGenerationOptions.cardType.localizedTitle(locale: appPreferences.resolvedLocale),
            viewModel.aiGenerationOptions.cardLevel.localizedTitle(locale: appPreferences.resolvedLocale),
            viewModel.aiGenerationOptions.localizedOutputLanguageSummary(locale: appPreferences.resolvedLocale)
        ].joined(separator: " · ")
    }

    private func header(safeTopInset: CGFloat) -> some View {
        HStack {
            Spacer(minLength: 0)

            ChromeSoftCircleSymbolButton(
                systemName: "xmark",
                accessibilityLabel: AppLocalization.string("Close", locale: appPreferences.resolvedLocale),
                action: requestCancel,
                symbolSize: UIConstants.Size.iconStandard
            )
            .frame(width: UIConstants.Size.actionButton, alignment: .trailing)
        }
        .frame(height: UIConstants.Size.actionButton)
        .padding(.top, safeTopInset + UIConstants.Spacing.tiny)
        .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
        .background(alignment: .top) {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.72),
                    Color.black.opacity(0.34),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: headerHeight + UIConstants.Spacing.extraLarge)
            .allowsHitTesting(false)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            if abs(headerHeight - newHeight) > 0.5 {
                headerHeight = newHeight
            }
        }
    }

    private var cardsCountCard: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HStack(alignment: .firstTextBaseline, spacing: UIConstants.Spacing.medium) {
                Text("Cards")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer(minLength: UIConstants.Spacing.small)
            }

            CardCountControl(
                value: viewModel.requestedCardCount,
                range: 1...100,
                presets: [5, 10, 15, 20, 30, 50, 100]
            ) { newValue in
                viewModel.setRequestedCardCount(newValue)
            }
        }
        .padding(UIConstants.Spacing.standard)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous))
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        summary: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        PlainGenerationSection(
            title: title,
            summary: summary,
            content: content
        )
    }

    private var generationSettingsContent: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            compactOptionRow(title: "Type") {
                HStack(spacing: UIConstants.Spacing.small) {
                    ForEach(AICardGenerationType.allCases) { type in
                        compactSelectionButton(
                            title: type.localizedTitle(locale: appPreferences.resolvedLocale),
                            isSelected: viewModel.aiGenerationOptions.cardType == type
                        ) {
                            viewModel.aiGenerationOptions.cardType = type
                        }
                    }
                }
            }

            compactOptionRow(title: "Level") {
                HStack(spacing: UIConstants.Spacing.small) {
                    ForEach(AICardGenerationLevel.allCases) { level in
                        compactSelectionButton(
                            title: level.localizedTitle(locale: appPreferences.resolvedLocale),
                            isSelected: viewModel.aiGenerationOptions.cardLevel == level
                        ) {
                            viewModel.aiGenerationOptions.cardLevel = level
                        }
                    }
                }
            }

            compactOptionRow(title: "Language") {
                outputLanguageCompactPicker
            }
        }
    }

    private var sourceCoverageContent: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            sourcePreviewStrip

            compactOptionRow(title: "Distribution") {
                HStack(spacing: UIConstants.Spacing.small) {
                    compactSelectionButton(
                        title: "Auto",
                        isSelected: viewModel.aiGenerationOptions.sourceDistributionMode == .auto
                    ) {
                        viewModel.setSourceDistributionMode(.auto)
                    }

                    compactSelectionButton(
                        title: "Manual",
                        isSelected: viewModel.aiGenerationOptions.sourceDistributionMode == .manual
                    ) {
                        viewModel.setSourceDistributionMode(.manual)
                    }
                }
            }

            if viewModel.aiGenerationOptions.sourceDistributionMode == .auto {
                cardsCountCard
            } else {
                manualCoverageEditor
            }
        }
    }

    @ViewBuilder
    private var sourcePreviewStrip: some View {
        if let source = viewModel.preparedAISource {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: UIConstants.Spacing.small) {
                        ForEach(source.previewItems) { item in
                            SourcePreviewCard(item: item) {
                                openSourcePreview(item)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var outputLanguageCompactPicker: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            HStack(spacing: UIConstants.Spacing.small) {
                compactSelectionButton(
                    title: "Auto",
                    isSelected: viewModel.aiGenerationOptions.outputLanguageMode == .auto
                ) {
                    viewModel.aiGenerationOptions.outputLanguageMode = .auto
                }

                compactSelectionButton(
                    title: "Manual",
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
                                Label(language.localizedDisplayName(locale: appPreferences.resolvedLocale), systemImage: "checkmark")
                            } else {
                                Text(language.localizedDisplayName(locale: appPreferences.resolvedLocale))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: UIConstants.Spacing.small) {
                        Text(
                            viewModel.aiGenerationOptions.manualOutputLanguage?.localizedDisplayName(locale: appPreferences.resolvedLocale)
                                ?? AppLocalization.string("Choose a language", locale: appPreferences.resolvedLocale)
                        )
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                        Spacer(minLength: UIConstants.Spacing.small)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, UIConstants.Spacing.standard)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func compactOptionRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.tiny) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content()
        }
    }

    private func compactSelectionButton(
        title: String,
        isSelected: Bool,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, UIConstants.Spacing.small)
                .padding(.vertical, 11)
                .background(
                    isSelected ? accent.opacity(0.16) : Color.white.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isSelected ? accent.opacity(0.42) : Color.white.opacity(0.07), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
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
            }
        }
    }

    private func bottomActionChrome(safeBottomInset: CGFloat) -> some View {
        BottomChromeContainer(
            kind: .selection,
            bottomPadding: max(safeBottomInset, UIConstants.Spacing.large),
            horizontalInset: UIConstants.Layout.bottomChromeSideInset,
            minimumHeightOverride: 64,
            innerHorizontalPaddingOverride: UIConstants.Spacing.tiny,
            innerVerticalPaddingOverride: UIConstants.Spacing.tiny
        ) {
            actionBar
        }
        .frame(maxWidth: maxContentWidth)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.34),
                    Color.black.opacity(0.68)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 180)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        HStack(spacing: UIConstants.Spacing.tiny) {
            Button(action: requestCancel) {
                Text(AppLocalization.string("Cancel", locale: appPreferences.resolvedLocale))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: requestPrimaryAction) {
                Text(AppLocalization.string("Generate", locale: appPreferences.resolvedLocale))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(accent, in: Capsule(style: .continuous))
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canConfirmAIGeneration)
            .opacity(viewModel.canConfirmAIGeneration ? 1 : 0.48)
        }
    }

    private func bottomActionClearance(safeBottomInset: CGFloat) -> CGFloat {
        max(safeBottomInset, UIConstants.Spacing.large)
            + UIConstants.Size.selectionToolbarBarHeight
            + UIConstants.Spacing.huge
    }

    private func requestCancel() {
        viewModel.clearsPendingAISourceOnSheetDismiss = true
        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss()
        } else {
            onCancel()
        }
    }

    private func requestPrimaryAction() {
        onPrimaryAction()
    }

    private func openSourcePreview(_ item: AIGenerationSourcePreviewItem) {
        sourcePreviewTask?.cancel()
        selectedSourcePreview = item
        selectedSourcePreviewImage = nil

        sourcePreviewTask = Task {
            let image = await viewModel.fullQualityPreviewImage(for: item)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                selectedSourcePreviewImage = image
            }
        }
    }

    private func closeSourcePreview() {
        sourcePreviewTask?.cancel()
        sourcePreviewTask = nil
        withAnimation(.easeInOut(duration: UIConstants.Animation.standard)) {
            selectedSourcePreview = nil
            selectedSourcePreviewImage = nil
        }
    }
}

private struct PlainGenerationSection<Content: View>: View {
    let title: String
    let summary: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
                Text(title)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: UIConstants.Spacing.small)

                Text(summary)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            .padding(.vertical, UIConstants.Spacing.small)

            content()
                .padding(.bottom, UIConstants.Spacing.standard)

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)
        }
    }
}
