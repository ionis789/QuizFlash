//
//  AIWorkspaceConversionViews.swift
//  QuizFlash
//
//  Conversion flow surfaces and helper views for the AI workspace.
//

import SwiftUI
import SwiftData

// MARK: - Shared Convert Editor

struct DeckConversionEditor: View {
    @Environment(AIWorkspaceCoordinator.self) private var coordinator

    let sourceDecks: [DeckModel]
    let managesSeedFromDeckList: Bool
    let showsDeckPicker: Bool
    let showsRuntimeSummary: Bool

    private var currentRequest: DeckCardConversionRequest? {
        coordinator.conversionSeed?.request
    }

    private var selectedSourceDeck: DeckModel? {
        guard let sourceDeckID = coordinator.conversionSeed?.sourceDeckID else { return nil }
        return sourceDecks.first(where: { $0.persistentModelID == sourceDeckID })
    }

    private var sourceDeckFingerprint: [Int] {
        sourceDecks.map { $0.persistentModelID.hashValue }
    }

    var body: some View {
        Group {
            if managesSeedFromDeckList && sourceDecks.isEmpty {
                ConversionUnavailableCard(
                    title: "No decks available",
                    message: "Create at least one deck before converting cards."
                )
            } else if let request = currentRequest {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                    if showsRuntimeSummary,
                       coordinator.conversionProgress != nil
                        || coordinator.conversionSummary != nil
                        || coordinator.conversionErrorMessage != nil {
                        AIWorkspaceRuntimeCard(coordinator: coordinator)
                    }

                    if showsDeckPicker {
                        sourceDeckPicker
                    }

                    ConversionSourceSection(
                        request: request,
                        tint: .orange,
                        onSelect: updateSourceKind
                    )
                    ConversionTargetSection(
                        request: request,
                        tint: .orange,
                        onSelect: updateTargetKind
                    )
                    ConversionDestinationSection(
                        request: request,
                        tint: .orange,
                        onSelect: updateDestination,
                        onUpdateTitle: updateNewDeckTitle
                    )
                }
            } else {
                ConversionUnavailableCard(
                    title: "Conversion unavailable",
                    message: managesSeedFromDeckList
                        ? "Pick a source deck to continue."
                        : "Start conversion from the deck screen and try again."
                )
            }
        }
        .onAppear {
            seedInitialDeckIfNeeded()
        }
        .onChange(of: sourceDeckFingerprint) { _, _ in
            seedInitialDeckIfNeeded()
        }
    }

    @ViewBuilder
    private var sourceDeckPicker: some View {
        ConversionSectionCard(title: "Deck") {
            if let seed = coordinator.conversionSeed {
                if sourceDecks.count > 1 {
                    Menu {
                        ForEach(sourceDecks) { deck in
                            Button {
                                seedConversion(for: deck)
                            } label: {
                                if deck.persistentModelID == seed.sourceDeckID {
                                    Label(deck.title, systemImage: "checkmark")
                                } else {
                                    Text(deck.title)
                                }
                            }
                        }
                    } label: {
                        ConversionDeckRow(
                            title: seed.sourceDeckTitle,
                            subtitle: "\(selectedSourceDeck?.cardCount ?? 0) cards",
                            showsDisclosure: true
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    ConversionDeckRow(
                        title: seed.sourceDeckTitle,
                        subtitle: "\(selectedSourceDeck?.cardCount ?? 0) cards",
                        showsDisclosure: false
                    )
                }
            }
        }
    }

    private func seedInitialDeckIfNeeded() {
        guard managesSeedFromDeckList else { return }
        guard !sourceDecks.isEmpty else {
            coordinator.dismissConversionConfiguration()
            return
        }

        if let selectedSourceDeck {
            if currentRequest == nil {
                seedConversion(for: selectedSourceDeck)
            }
            return
        }

        if let firstDeck = sourceDecks.first {
            seedConversion(for: firstDeck)
        }
    }

    private func seedConversion(for deck: DeckModel) {
        let orderedCards = deck.cards.sorted {
            if $0.cardNumber == $1.cardNumber {
                return $0.createdAt < $1.createdAt
            }
            return $0.cardNumber < $1.cardNumber
        }
        let sources = orderedCards.map {
            DeckCardConversionSourceDescriptor(id: $0.persistentModelID, kind: $0.kind)
        }
        guard let request = DeckCardConversionRequest.makeWholeDeckRequest(
            sources: sources,
            deckTitle: deck.title,
            preferredSourceKind: currentRequest?.sourceKind,
            preferredTargetKind: currentRequest?.targetKind,
            existingRequest: currentRequest
        ) else {
            return
        }

        _ = coordinator.seedConversion(
            request: request,
            sourceDeck: deck,
            showsConfiguration: false,
            activatesWorkspaceContext: false
        )
    }

    private func updateSourceKind(_ kind: CardKind) {
        coordinator.updateConversionDraft { draft in
            draft.selectSourceKind(kind)
        }
    }

    private func updateTargetKind(_ kind: CardKind) {
        coordinator.updateConversionDraft { draft in
            draft.updateTargetKind(kind)
        }
    }

    private func updateDestination(_ destination: DeckCardConversionDestinationOption) {
        coordinator.updateConversionDraft { draft in
            draft.destination = destination
        }
    }

    private func updateNewDeckTitle(_ title: String) {
        coordinator.updateConversionDraft { draft in
            draft.newDeckTitle = title
        }
    }
}

// MARK: - Shared Conversion UI

private struct ConversionSourceSection: View {
    let request: DeckCardConversionRequest
    let tint: Color
    let onSelect: (CardKind) -> Void

    var body: some View {
        ConversionSectionCard(title: "Source") {
            if request.availableSourceKinds.count == 1,
               let sourceKind = request.selectedSourceKind {
                ConversionStaticSourceRow(
                    kind: sourceKind,
                    subtitle: "\(request.sourceCount(for: sourceKind)) card\(request.sourceCount(for: sourceKind) == 1 ? "" : "s")",
                    tint: tint
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(request.availableSourceKinds, id: \.self) { kind in
                        ConversionKindRow(
                            kind: kind,
                            subtitle: "\(request.sourceCount(for: kind)) card\(request.sourceCount(for: kind) == 1 ? "" : "s")",
                            isSelected: request.selectedSourceKind == kind,
                            tint: tint,
                            action: { onSelect(kind) }
                        )
                    }
                }
            }
        }
    }
}

private struct ConversionTargetSection: View {
    let request: DeckCardConversionRequest
    let tint: Color
    let onSelect: (CardKind) -> Void

    var body: some View {
        ConversionSectionCard(title: "Convert Into") {
            VStack(spacing: 10) {
                ForEach(CardKind.allCases, id: \.self) { kind in
                    let isAvailable = request.isTargetKindAvailable(kind)
                    ConversionKindRow(
                        kind: kind,
                        subtitle: conversionTargetSubtitle(kind),
                        isSelected: request.targetKind == kind,
                        isDisabled: !isAvailable,
                        tint: tint,
                        action: {
                            guard isAvailable else { return }
                            onSelect(kind)
                        }
                    )
                }
            }
        }
    }
}

private struct ConversionDestinationSection: View {
    let request: DeckCardConversionRequest
    let tint: Color
    let onSelect: (DeckCardConversionDestinationOption) -> Void
    let onUpdateTitle: (String) -> Void

    var body: some View {
        ConversionSectionCard(title: "Save Result") {
            VStack(spacing: UIConstants.Spacing.small) {
                ForEach(DeckCardConversionDestinationOption.allCases) { option in
                    ConversionOptionRow(
                        title: option.title,
                        subtitle: option.subtitle,
                        systemImage: option == .sameDeck
                            ? "square.stack.3d.up.fill"
                            : "square.stack.3d.up.badge.a.fill",
                        isSelected: request.destination == option,
                        tint: tint,
                        action: { onSelect(option) }
                    )
                }

                if request.destination == .newDeck {
                    TextField(
                        "New deck title",
                        text: Binding(
                            get: { request.newDeckTitle },
                            set: onUpdateTitle
                        )
                    )
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
                    }
                }
            }
        }
    }
}

struct ConversionStartBar: View {
    let request: DeckCardConversionRequest
    let tint: Color
    let horizontalInset: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: UIConstants.Spacing.small) {
                Text("Convert")
                    .font(.system(size: 17, weight: .bold, design: .rounded))

                Spacer(minLength: 0)

                Text("\(request.sourceCount) card\(request.sourceCount == 1 ? "" : "s")")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(request.canStart ? .white.opacity(0.88) : .secondary)
            }
            .foregroundStyle(request.canStart ? .white : .secondary)
            .padding(.horizontal, 18)
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .background(buttonBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(buttonBorder, lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .disabled(!request.canStart)
        .padding(.horizontal, horizontalInset)
        .padding(.bottom, UIConstants.Spacing.large)
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

    private var buttonBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                request.canStart
                    ? tint
                    : Color(uiColor: .tertiarySystemFill)
            )
    }

    private var buttonBorder: Color {
        request.canStart
            ? tint.opacity(0.35)
            : Color.white.opacity(0.06)
    }
}

private struct ConversionUnavailableCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sectionBackground)
    }
}

private struct ConversionSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.45)

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sectionBackground)
    }
}

private struct ConversionDeckRow: View {
    let title: String
    let subtitle: String
    let showsDisclosure: Bool
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(spacing: 12) {
            conversionOptionIcon(systemImage: "rectangle.stack.fill", tint: themeManager.accentColor.color)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(subtitle)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
    }
}

private struct ConversionStaticSourceRow: View {
    let kind: CardKind
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            conversionOptionIcon(systemImage: kind.conversionSystemImage, tint: tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(kind.displayTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text("Auto")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
    }
}

private struct ConversionOptionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                conversionOptionIcon(systemImage: systemImage, tint: isSelected ? tint : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isSelected ? tint : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                rowBackground(
                    isSelected: isSelected,
                    tint: tint
                )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ConversionKindRow: View {
    let kind: CardKind
    let subtitle: String
    let isSelected: Bool
    var isDisabled: Bool = false
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                conversionOptionIcon(
                    systemImage: kind.conversionSystemImage,
                    tint: isDisabled ? .secondary.opacity(0.65) : (isSelected ? tint : .secondary)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.displayTitle)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(isDisabled ? "Unavailable" : subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: indicatorSymbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(indicatorTint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                rowBackground(
                    isSelected: isSelected,
                    tint: tint
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.56 : 1)
    }

    private var indicatorSymbol: String {
        if isDisabled {
            return "slash.circle.fill"
        }
        return isSelected ? "checkmark.circle.fill" : "circle"
    }

    private var indicatorTint: Color {
        if isDisabled {
            return .secondary
        }
        return isSelected ? tint : .secondary
    }
}

private func conversionOptionIcon(systemImage: String, tint: Color) -> some View {
    ZStack {
        Circle()
            .fill(tint.opacity(0.14))
            .frame(width: 30, height: 30)

        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
    }
}

private func conversionTargetSubtitle(_ kind: CardKind) -> String {
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

var sectionBackground: some View {
    RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.8)
        }
}

var rowBackground: some View {
    RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(uiColor: .tertiarySystemFill))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 0.6)
        }
}

func rowBackground(isSelected: Bool, tint: Color) -> some View {
    RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(isSelected ? tint.opacity(0.16) : Color(uiColor: .tertiarySystemFill))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isSelected ? tint.opacity(0.28) : Color.white.opacity(0.04),
                    lineWidth: 0.8
                )
        }
}
