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

private let kAIWorkspaceConversionChromeSpace = "AIWorkspaceConversionChromeSpace"

struct AIWorkspaceConversionSheetView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Bindable var coordinator: AIWorkspaceCoordinator
    let sourceDecks: [DeckModel]
    let onSelectSourceDeck: (DeckModel) -> Void
    let onStart: () -> Void

    @State private var headerHeight: CGFloat = 0

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    private var conversionTint: Color {
        .orange
    }

    private var horizontalInset: CGFloat {
        horizontalSizeClass == .compact
            ? UIConstants.Layout.compactScreenEdgeInset
            : UIConstants.Layout.screenEdgeInset
    }

    private var maxContentWidth: CGFloat {
        UIConstants.isPad ? 820 : .infinity
    }

    private var sheetBackground: some View {
        ZStack {
            Color(uiColor: .secondarySystemGroupedBackground)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.045),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            StandardSheetTopStripBackground()
                .opacity(0.34)
        }
    }

    private var currentRequest: DeckCardConversionRequest? {
        coordinator.conversionSeed?.request
    }

    private var selectedSourceDeck: DeckModel? {
        guard let sourceDeckID = coordinator.conversionSeed?.sourceDeckID else { return nil }
        return sourceDecks.first(where: { $0.persistentModelID == sourceDeckID })
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                sheetBackground
                    .ignoresSafeArea()

                contentScroll
            }
            .overlay(alignment: .top) {
                header(safeTopInset: proxy.safeAreaInsets.top)
            }
            .overlay(alignment: .bottomTrailing) {
                if let request = currentRequest {
                    floatingStartButton(
                        request: request,
                        bottomInset: max(proxy.safeAreaInsets.bottom, UIConstants.Spacing.large)
                    )
                }
            }
            .coordinateSpace(name: kAIWorkspaceConversionChromeSpace)
        }
    }

    private var contentScroll: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                if let request = currentRequest {
                    overviewCard(request)
                    sourceDeckSection
                    scopeSection(request)
                    sourceTypesSection(request)
                    targetTypeSection(request)
                    destinationSection(request)
                } else {
                    unavailableState
                }
            }
            .frame(maxWidth: maxContentWidth)
            .padding(.horizontal, horizontalInset)
            .padding(.top, headerHeight + UIConstants.Spacing.large)
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.hidden)
    }

    private func header(safeTopInset: CGFloat) -> some View {
        VStack(spacing: UIConstants.Spacing.small) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 48, height: 5)
                .accessibilityHidden(true)

            CollapsibleTitleNavigationBar(
                coordinateSpaceName: kAIWorkspaceConversionChromeSpace,
                horizontalInset: 0,
                appliesTopNavigationChrome: false,
                onHeightChange: { newHeight in
                    if abs(headerHeight - newHeight) > 0.5 {
                        headerHeight = newHeight
                    }
                }
            ) {
                ChromeCirclePlaceholder()
            } center: { maxWidth in
                CollapsibleTitlePill(
                    title: "Convert Cards",
                    maxWidth: maxWidth,
                    isVisible: true,
                    fallbackTitle: "Convert Cards"
                )
            } trailing: {
                ChromeCircleIconButton(systemName: "xmark") {
                    coordinator.dismissConversionConfiguration()
                }
            }
        }
        .padding(.top, safeTopInset + UIConstants.Spacing.tiny)
        .padding(.horizontal, horizontalInset)
    }

    private func overviewCard(_ request: DeckCardConversionRequest) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text("AI WORKSPACE")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.45)

            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                Text("Convert Cards")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)

                Text(overviewSubtitle(for: request))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: UIConstants.Spacing.small) {
                summaryChip(
                    "\(request.sourceCount) cards",
                    systemImage: "rectangle.stack.fill"
                )
                .statusTextMotion(trigger: request.sourceCount)

                summaryChip(
                    request.scope.title,
                    systemImage: "line.3.horizontal.decrease.circle.fill"
                )

                summaryChip(
                    request.targetKind.displayTitle,
                    systemImage: request.targetKind.conversionSystemImage
                )
            }
        }
        .padding(UIConstants.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetStyle(cornerRadius: 30)
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private var sourceDeckSection: some View {
        sectionCard(
            title: "Source Deck",
            subtitle: "Choose which saved deck should feed the conversion."
        ) {
            if let seed = coordinator.conversionSeed {
                if sourceDecks.count > 1 {
                    Menu {
                        ForEach(sourceDecks) { deck in
                            Button {
                                onSelectSourceDeck(deck)
                            } label: {
                                if deck.persistentModelID == seed.sourceDeckID {
                                    Label(deck.title, systemImage: "checkmark")
                                } else {
                                    Text(deck.title)
                                }
                            }
                        }
                    } label: {
                        sourceDeckRow(seed: seed, showsDisclosure: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    sourceDeckRow(seed: seed, showsDisclosure: false)
                }
            } else {
                optionRow(
                    title: "No deck selected",
                    subtitle: "Pick a source deck to continue.",
                    systemImage: "rectangle.stack.fill",
                    isSelected: false,
                    action: {}
                )
                .allowsHitTesting(false)
            }
        }
    }

    private func sourceDeckRow(
        seed: AIWorkspaceConversionSeed,
        showsDisclosure: Bool
    ) -> some View {
        HStack(spacing: UIConstants.Spacing.medium) {
            optionIcon(
                systemImage: "rectangle.stack.fill",
                tint: accent
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(seed.sourceDeckTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("\(selectedSourceDeck?.cardCount ?? 0) cards available")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if showsDisclosure {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(selectionBackgroundColor(isSelected: true))
        }
        .overlay {
            selectionBorder(isSelected: true)
        }
    }

    private func scopeSection(_ request: DeckCardConversionRequest) -> some View {
        sectionCard(
            title: "What To Convert",
            subtitle: "Choose the slice of cards that should be sent to AI."
        ) {
            VStack(spacing: UIConstants.Spacing.small) {
                ForEach(request.availableScopes) { scope in
                    optionRow(
                        title: scope.title,
                        subtitle: scope.subtitle,
                        systemImage: "line.3.horizontal.decrease.circle.fill",
                        badgeText: scopeSummary(scope, request: request),
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
        sectionCard(
            title: "Source Types",
            subtitle: "Keep only the source card kinds you want to transform."
        ) {
            if request.eligibleSourceKinds.isEmpty {
                Text("No compatible source kinds remain for this target.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVGrid(columns: gridColumns, spacing: UIConstants.Spacing.small) {
                    ForEach(request.eligibleSourceKinds, id: \.self) { kind in
                        kindTile(
                            kind: kind,
                            subtitle: "\(request.sourceCount(for: kind)) card\(request.sourceCount(for: kind) == 1 ? "" : "s")",
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
    }

    private func targetTypeSection(_ request: DeckCardConversionRequest) -> some View {
        sectionCard(
            title: "Convert Into",
            subtitle: "Pick the destination format the model should generate."
        ) {
            LazyVGrid(columns: gridColumns, spacing: UIConstants.Spacing.small) {
                ForEach(CardKind.allCases, id: \.self) { kind in
                    kindTile(
                        kind: kind,
                        subtitle: targetKindSubtitle(kind),
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
        sectionCard(
            title: "Save Result",
            subtitle: "Keep the converted cards in the same deck or send them into a sibling deck."
        ) {
            VStack(spacing: UIConstants.Spacing.small) {
                ForEach(DeckCardConversionDestinationOption.allCases) { option in
                    optionRow(
                        title: option.title,
                        subtitle: option.subtitle,
                        systemImage: option == .sameDeck ? "square.stack.3d.up.fill" : "square.stack.3d.up.badge.a.fill",
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
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(selectionBackgroundColor(isSelected: true))
                }
                .overlay {
                    selectionBorder(isSelected: true)
                }
            }
        }
    }

    private func floatingStartButton(
        request: DeckCardConversionRequest,
        bottomInset: CGFloat
    ) -> some View {
        HStack {
            Spacer()

            Button(action: onStart) {
                HStack(spacing: UIConstants.Spacing.small) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Convert")
                            .font(.system(size: 16, weight: .bold, design: .rounded))

                        Text(buttonSubtitle(for: request))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }

                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundStyle(request.canStart ? conversionTint : .secondary)
                .padding(.horizontal, 18)
                .frame(height: 58)
                .glassButton(shape: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(!request.canStart)
            .opacity(request.canStart ? 1 : 0.58)
        }
        .padding(.horizontal, horizontalInset)
        .padding(.bottom, bottomInset)
        .background(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.clear
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .ignoresSafeArea()
        }
    }

    private var unavailableState: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text("Conversion Unavailable")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("The conversion request is no longer available. Reopen the flow and try again.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(UIConstants.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetStyle(cornerRadius: 30)
    }

    private var gridColumns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    private func sectionCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
        .padding(UIConstants.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetStyle(cornerRadius: UIConstants.Radius.large)
        .overlay {
            RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private func optionRow(
        title: String,
        subtitle: String,
        systemImage: String,
        badgeText: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: UIConstants.Spacing.medium) {
                optionIcon(
                    systemImage: systemImage,
                    tint: isSelected ? conversionTint : .secondary
                )

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

                if let badgeText {
                    summaryChip(badgeText, systemImage: nil)
                }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isSelected ? conversionTint : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(selectionBackgroundColor(isSelected: isSelected))
            }
            .overlay {
                selectionBorder(isSelected: isSelected)
            }
        }
        .buttonStyle(.plain)
    }

    private func kindTile(
        kind: CardKind,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                HStack(spacing: UIConstants.Spacing.small) {
                    optionIcon(
                        systemImage: kind.conversionSystemImage,
                        tint: isSelected ? conversionTint : .secondary
                    )

                    Spacer(minLength: 0)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isSelected ? conversionTint : .secondary)
                }

                Text(kind.displayTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(selectionBackgroundColor(isSelected: isSelected))
            }
            .overlay {
                selectionBorder(isSelected: isSelected)
            }
        }
        .buttonStyle(.plain)
    }

    private func optionIcon(
        systemImage: String,
        tint: Color
    ) -> some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.14))
                .frame(width: 34, height: 34)

            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
    }

    private func selectionBackgroundColor(isSelected: Bool) -> Color {
        isSelected ? Color.white.opacity(0.09) : Color.white.opacity(0.04)
    }

    private func selectionBorder(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(
                isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.06),
                lineWidth: 0.8
            )
    }

    private func summaryChip(
        _ text: String,
        systemImage: String?
    ) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }

            Text(text)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05), in: Capsule())
    }

    private func overviewSubtitle(for request: DeckCardConversionRequest) -> String {
        let deckTitle = selectedSourceDeck?.title ?? coordinator.conversionSeed?.sourceDeckTitle ?? "your deck"
        return "Choose the exact scope, source types, and destination for converting cards from \(deckTitle) into \(request.targetKind.displayTitle.lowercased()) cards."
    }

    private func buttonSubtitle(for request: DeckCardConversionRequest) -> String {
        let typeCount = request.normalizedSourceKindFilters.count
        let noun = typeCount == 1 ? "type" : "types"
        return "\(request.sourceCount) cards · \(typeCount) \(noun)"
    }

    private func targetKindSubtitle(_ kind: CardKind) -> String {
        switch kind {
        case .flashcard:
            return "Question and answer"
        case .match:
            return "Prompt and pair"
        case .quiz:
            return "Multiple choice"
        case .write:
            return "Typed answer"
        }
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
