//
//  AIWorkspaceViews.swift
//  QuizFlash
//
//  Shared UI surfaces for the global AI workspace.
//

import SwiftUI
import SwiftData

// MARK: - Floating Status

struct FloatingAIWorkspaceStatusMenu: View {
    let status: AIWorkspaceFloatingStatus
    var bottomPadding: CGFloat
    let onOpenWorkspace: () -> Void
    var onPauseResume: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    private var tint: Color {
        switch status.phase {
        case .failed:
            return .red
        case .completed:
            return .green
        case .paused:
            return .orange
        case .preparing, .running:
            return status.kind == .conversion ? .orange : accent
        }
    }

    var body: some View {
        workspaceButton
            .padding(.trailing, UIConstants.Layout.compactScreenEdgeInset)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .transition(.scale(scale: 0.92, anchor: .trailing).combined(with: .opacity))
    }

    private var workspaceButton: some View {
        FloatingAIWorkspaceCapsuleContainer {
            HStack(spacing: UIConstants.Spacing.small) {
                Button(action: onOpenWorkspace) {
                    compactContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open AI workspace")

                if let onPauseResume {
                    Button(action: onPauseResume) {
                        Image(systemName: pauseResumeSymbol)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(tint)
                            .frame(width: 24, height: 24)
                            .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(status.phase == .paused ? "Resume AI workspace job" : "Pause AI workspace job")
                }

                if let onCancel {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel AI workspace job")
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var compactContent: some View {
        HStack(spacing: UIConstants.Spacing.small) {
            FloatingAIWorkspaceStatusIndicator(
                countText: compactCountText,
                tint: tint,
                fallbackSystemImage: status.systemImage
            )

            if compactCountText == nil {
                Text(compactTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
    }

    private var compactTitle: String {
        switch status.phase {
        case .completed:
            return "Done"
        case .failed:
            return "Error"
        case .preparing, .running, .paused:
            return status.kind == .conversion ? "Convert" : "Generate"
        }
    }

    private var compactCountText: String? {
        if status.phase == .preparing || status.phase == .running || status.phase == .paused,
           let progressLabel = status.progressLabel {
            return progressLabel
        }
        return nil
    }

    private var pauseResumeSymbol: String {
        status.phase == .paused ? "play.fill" : "pause.fill"
    }
}

private struct FloatingAIWorkspaceCapsuleContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, UIConstants.Spacing.standard)
            .frame(minWidth: UIConstants.Size.capsuleHeight)
            .frame(height: UIConstants.Size.capsuleHeight)
            .glassButton(shape: .capsule)
    }
}

private struct FloatingAIWorkspaceStatusIndicator: View {
    let countText: String?
    let tint: Color
    let fallbackSystemImage: String

    var body: some View {
        if let countText {
            VStack(spacing: 2) {
                Text(countText)
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .statusTextMotion(trigger: countText)

                AIGenerationActivityDots(color: tint)
                    .frame(minWidth: 22)
            }
            .fixedSize(horizontal: true, vertical: false)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: countText)
        } else {
            Image(systemName: fallbackSystemImage)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
        }
    }
}

// MARK: - Conversion Configuration

struct AIWorkspaceConversionConfigurationCard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Bindable var coordinator: AIWorkspaceCoordinator
    let sourceDecks: [DeckModel]
    let onSelectSourceDeck: (DeckModel) -> Void
    let onStart: () -> Void

    private var horizontalInset: CGFloat {
        horizontalSizeClass == .compact
            ? UIConstants.Layout.compactScreenEdgeInset
            : UIConstants.Layout.screenEdgeInset
    }

    private var maxCardHeight: CGFloat {
        UIConstants.isPad ? 640 : 520
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                HStack(alignment: .top, spacing: UIConstants.Spacing.small) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI WORKSPACE")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .tracking(0.45)

                        Text("Convert Cards")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)
                    }

                    Spacer(minLength: 0)

                    Button {
                        coordinator.dismissConversionConfiguration()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.05), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                if let request = coordinator.conversionSeed?.request {
                    VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                        sourceDeckSection
                        scopeSection(request)
                        sourceTypesSection(request)
                        targetTypeSection(request)
                        destinationSection(request)
                        startSection(request)
                    }
                }
            }
            .padding(UIConstants.Spacing.large)
            .padding(.horizontal, horizontalInset - UIConstants.Layout.cardListEdgeInset)
        }
        .frame(maxHeight: maxCardHeight)
        .widgetStyle(cornerRadius: UIConstants.Radius.large)
    }

    @ViewBuilder
    private var sourceDeckSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            sectionTitle("Source Deck")

            if let seed = coordinator.conversionSeed {
                Menu {
                    ForEach(sourceDecks) { deck in
                        Button {
                            onSelectSourceDeck(deck)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(deck.title)
                                Text("\(deck.cardCount) cards")
                                    .font(.caption)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: UIConstants.Spacing.small) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(seed.sourceDeckTitle)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)

                            Text("\(sourceDecks.first(where: { $0.persistentModelID == seed.sourceDeckID })?.cardCount ?? 0) cards")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.75)
                    }
                }
                .buttonStyle(.plain)
            } else {
                compactSelectionRow(
                    title: "No deck selected",
                    subtitle: "Choose a source deck to start conversion.",
                    isSelected: false
                ) { }
                .allowsHitTesting(false)
            }
        }
    }

    private func scopeSection(_ request: DeckCardConversionRequest) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            sectionTitle("Scope")

            VStack(spacing: UIConstants.Spacing.small) {
                ForEach(request.availableScopes) { scope in
                    compactSelectionRow(
                        title: scope.title,
                        subtitle: scopeSummary(scope, request: request),
                        isSelected: request.scope == scope
                    ) {
                        coordinator.updateConversionDraft { draft in
                            draft.updateScope(scope)
                        }
                    }
                }
            }
        }
    }

    private func sourceTypesSection(_ request: DeckCardConversionRequest) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            sectionTitle("Source Types")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: UIConstants.Spacing.small) {
                ForEach(request.eligibleSourceKinds, id: \.self) { kind in
                    sourceTypeChip(
                        kind: kind,
                        count: request.sourceCount(for: kind),
                        isSelected: request.normalizedSourceKindFilters.contains(kind)
                    ) {
                        coordinator.updateConversionDraft { draft in
                            draft.toggleSourceKind(kind)
                        }
                    }
                }
            }
        }
    }

    private func targetTypeSection(_ request: DeckCardConversionRequest) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            sectionTitle("Target Type")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: UIConstants.Spacing.small) {
                ForEach(CardKind.allCases, id: \.self) { kind in
                    sourceTypeChip(
                        kind: kind,
                        count: nil,
                        isSelected: request.targetKind == kind
                    ) {
                        coordinator.updateConversionDraft { draft in
                            draft.updateTargetKind(kind)
                        }
                    }
                }
            }
        }
    }

    private func destinationSection(_ request: DeckCardConversionRequest) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            sectionTitle("Destination")

            VStack(spacing: UIConstants.Spacing.small) {
                ForEach(DeckCardConversionDestinationOption.allCases) { option in
                    compactSelectionRow(
                        title: option.title,
                        subtitle: option.subtitle,
                        isSelected: request.destination == option
                    ) {
                        coordinator.updateConversionDraft { draft in
                            draft.destination = option
                        }
                    }
                }
            }

            if request.destination == .newDeck {
                TextField(
                    "New deck title",
                    text: Binding(
                        get: { coordinator.conversionSeed?.request.newDeckTitle ?? "" },
                        set: { newValue in
                            coordinator.updateConversionDraft { draft in
                                draft.newDeckTitle = newValue
                            }
                        }
                    )
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.75)
                }
            }
        }
    }

    private func startSection(_ request: DeckCardConversionRequest) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            sectionTitle("Run")

            HStack(spacing: UIConstants.Spacing.small) {
                summaryChip("\(request.sourceCount) cards")
                summaryChip("\(request.normalizedSourceKindFilters.count) source type\(request.normalizedSourceKindFilters.count == 1 ? "" : "s")")
            }

            Button {
                onStart()
            } label: {
                Text("Start Conversion")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(
                            colors: [ThemeManager.shared.accentColor.color, .orange],
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

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .tracking(0.45)
    }

    private func compactSelectionRow(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: UIConstants.Spacing.small) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isSelected ? ThemeManager.shared.accentColor.color : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(isSelected ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.12 : 0.06), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    private func sourceTypeChip(
        kind: CardKind,
        count: Int?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: UIConstants.Spacing.small) {
                    Image(systemName: kind.conversionSystemImage)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(kind.displayTitle)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? .primary : .secondary)

                if let count {
                    Text("\(count) card\(count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(isSelected ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.12 : 0.06), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    private func summaryChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.05), in: Capsule())
    }

    private func scopeSummary(
        _ scope: DeckCardConversionScopeOption,
        request: DeckCardConversionRequest
    ) -> String {
        switch scope {
        case .wholeDeck:
            return "\(request.wholeDeckSources.count) cards"
        case .recommendedCards:
            return "\(request.recommendedCardCount) cards"
        case .selectedCards:
            return "\(request.selectedCardCount) cards"
        case .singleCard:
            return "\(request.singleSources.count) card"
        }
    }
}

struct AIWorkspaceFailureCard: View {
    let title: String
    let message: String
    let tint: Color
    var onRetry: (() -> Void)? = nil
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HStack(spacing: UIConstants.Spacing.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: UIConstants.Spacing.small) {
                if let onRetry {
                    Button("Resume", action: onRetry)
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(tint, in: Capsule())
                        .foregroundStyle(.white)
                }

                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                    .foregroundStyle(.primary)
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .padding(UIConstants.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        }
    }
}

struct DeckInlineConversionConfigurationCard: View {
    let sourceDeckTitle: String
    let sourceDeckCardCount: Int
    let request: DeckCardConversionRequest
    let onDismiss: () -> Void
    let onUpdateScope: (DeckCardConversionScopeOption) -> Void
    let onToggleSourceKind: (CardKind) -> Void
    let onUpdateTargetKind: (CardKind) -> Void
    let onUpdateDestination: (DeckCardConversionDestinationOption) -> Void
    let onUpdateNewDeckTitle: (String) -> Void
    let onStart: () -> Void

    private var maxCardHeight: CGFloat {
        UIConstants.isPad ? 620 : 500
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                HStack(alignment: .top, spacing: UIConstants.Spacing.small) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI WORKSPACE")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .tracking(0.45)

                        Text("Convert Cards")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)
                    }

                    Spacer(minLength: 0)

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.05), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: UIConstants.Spacing.small) {
                    deckSummaryChip(sourceDeckTitle, systemImage: "rectangle.stack")
                    deckSummaryChip("\(sourceDeckCardCount) cards", systemImage: "number")
                    deckSummaryChip(request.scope.title, systemImage: "line.3.horizontal.decrease.circle")
                }

                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    compactSectionTitle("Scope")
                    ForEach(request.availableScopes) { scope in
                        configurationRow(
                            title: scope.title,
                            subtitle: scopeSummary(scope, request: request),
                            isSelected: request.scope == scope
                        ) {
                            onUpdateScope(scope)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    compactSectionTitle("Source Types")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: UIConstants.Spacing.small) {
                        ForEach(request.eligibleSourceKinds, id: \.self) { kind in
                            compactKindChip(
                                kind: kind,
                                count: request.sourceCount(for: kind),
                                isSelected: request.normalizedSourceKindFilters.contains(kind)
                            ) {
                                onToggleSourceKind(kind)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    compactSectionTitle("Target")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: UIConstants.Spacing.small) {
                        ForEach(CardKind.allCases, id: \.self) { kind in
                            compactKindChip(
                                kind: kind,
                                count: nil,
                                isSelected: request.targetKind == kind
                            ) {
                                onUpdateTargetKind(kind)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    compactSectionTitle("Destination")
                    ForEach(DeckCardConversionDestinationOption.allCases) { option in
                        configurationRow(
                            title: option.title,
                            subtitle: option.subtitle,
                            isSelected: request.destination == option
                        ) {
                            onUpdateDestination(option)
                        }
                    }

                    if request.destination == .newDeck {
                        TextField("New deck title", text: Binding(
                            get: { request.newDeckTitle },
                            set: onUpdateNewDeckTitle
                        ))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.75)
                        }
                    }
                }

                Button(action: onStart) {
                    Text("Convert")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            LinearGradient(
                                colors: [ThemeManager.shared.accentColor.color, .orange],
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
        }
        .frame(maxHeight: maxCardHeight)
        .widgetStyle(cornerRadius: UIConstants.Radius.large)
    }

    private func compactSectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .tracking(0.45)
    }

    private func deckSummaryChip(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold, design: .rounded))
            Text(text)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05), in: Capsule())
    }

    private func configurationRow(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: UIConstants.Spacing.small) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isSelected ? ThemeManager.shared.accentColor.color : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(isSelected ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.12 : 0.06), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    private func compactKindChip(
        kind: CardKind,
        count: Int?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Image(systemName: kind.conversionSystemImage)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(kind.displayTitle)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? .primary : .secondary)

                if let count {
                    Text("\(count) cards")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(isSelected ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.12 : 0.06), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    private func scopeSummary(
        _ scope: DeckCardConversionScopeOption,
        request: DeckCardConversionRequest
    ) -> String {
        switch scope {
        case .wholeDeck:
            return "\(request.wholeDeckSources.count) cards"
        case .recommendedCards:
            return "\(request.recommendedCardCount) cards"
        case .selectedCards:
            return "\(request.selectedCardCount) cards"
        case .singleCard:
            return "\(request.singleSources.count) card"
        }
    }
}

// MARK: - Runtime Card

struct AIWorkspaceRuntimeCard: View {
    @Environment(\.modelContext) private var context

    @Bindable var coordinator: AIWorkspaceCoordinator
    var onOpenDestinationDeck: ((PersistentIdentifier) -> Void)? = nil

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    var body: some View {
        Group {
            if let errorMessage = coordinator.conversionErrorMessage {
                errorCard(errorMessage)
            } else if let progress = coordinator.conversionProgress {
                progressCard(progress)
            } else if let summary = coordinator.conversionSummary {
                summaryCard(summary)
            }
        }
    }

    private func progressCard(_ progress: DeckCardConversionProgress) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text("AI WORKSPACE")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.45)

            HStack(alignment: .firstTextBaseline, spacing: UIConstants.Spacing.small) {
                Text(coordinator.canResumeConversion ? "Conversion paused" : "Converting cards")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Text("\(progress.completedCount)/\(progress.totalCount)")
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(progress.statusMessage)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: progress.fractionCompleted)
                .tint(.orange)

            HStack(spacing: UIConstants.Spacing.small) {
                runtimeChip("\(progress.createdCount) created", tint: accent)
                runtimeChip("\(progress.skippedCount) skipped", tint: .secondary)
                if progress.failedCount > 0 {
                    runtimeChip("\(progress.failedCount) failed", tint: .red)
                }
            }

            if coordinator.canResumeConversion {
                HStack(spacing: UIConstants.Spacing.small) {
                    Button("Resume") {
                        coordinator.resumeConversion(context: context)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(Color.white.opacity(0.06), in: Capsule())

                    Button("Dismiss") {
                        coordinator.dismissConversionOutcome()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(Color.white.opacity(0.04), in: Capsule())
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
            }
        }
        .padding(UIConstants.Spacing.large)
        .widgetStyle(cornerRadius: UIConstants.Radius.large)
    }

    private func summaryCard(_ summary: DeckCardConversionSummary) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text("AI WORKSPACE")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.45)

            Text(summary.createdCount == 1
                 ? "1 \(summary.targetKind.displayTitle) card created"
                 : "\(summary.createdCount) \(summary.targetKind.displayTitle) cards created")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(summary.destinationDeckTitle)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: UIConstants.Spacing.small) {
                runtimeChip("\(summary.skippedCount) skipped", tint: .secondary)
                if summary.failedCount > 0 {
                    runtimeChip("\(summary.failedCount) failed", tint: .red)
                }
            }

            HStack(spacing: UIConstants.Spacing.small) {
                if let destinationDeckID = summary.destinationDeckID,
                   summary.destination == .newDeck {
                    Button("Open Deck") {
                        onOpenDestinationDeck?(destinationDeckID)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(Color.white.opacity(0.06), in: Capsule())
                }

                Button("Dismiss") {
                    coordinator.dismissConversionOutcome()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Color.white.opacity(0.04), in: Capsule())
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .padding(UIConstants.Spacing.large)
        .widgetStyle(cornerRadius: UIConstants.Radius.large)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text("AI WORKSPACE")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.45)

            Text("Conversion stopped")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(.primary)

            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: UIConstants.Spacing.small) {
                if coordinator.canResumeConversion {
                    Button("Resume") {
                        coordinator.resumeConversion(context: context)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(Color.white.opacity(0.06), in: Capsule())
                }

                Button("Dismiss") {
                    coordinator.dismissConversionOutcome()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Color.white.opacity(0.04), in: Capsule())
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .padding(UIConstants.Spacing.large)
        .widgetStyle(cornerRadius: UIConstants.Radius.large)
    }

    private func runtimeChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.05), in: Capsule())
    }
}
