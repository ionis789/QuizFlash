//
//  DeckCardGridView.swift
//  QuizFlash
//
//  Image-backed deck card grid optimized for smooth scrolling and tab persistence.
//

import SwiftUI
import SwiftData
import ImageIO

// =============================================================================
// MARK: - DeckCardGridView
// =============================================================================

struct DeckCardGridView: View {
    struct CardSection: Identifiable {
        let id: String
        let title: String
        let cards: [GridCardInfo]
        var dateForSorting: Date? = nil
    }

    let cards: [CardSection]
    let isSelecting: Bool
    let selectedCards: Set<PersistentIdentifier>
    let isInitialWarmReady: Bool
    let previewEntryProvider: (GridCardInfo) -> DeckCardSurfaceEntry
    let onLayoutResolved: (Int, CGFloat) -> Void
    let onCardVisibilityChanged: (PersistentIdentifier, Bool) -> Void

    var onToggleSelection: (GridCardInfo) -> Void
    var onTapCard: (GridCardInfo) -> Void
    var onOpenCardMenu: (GridCardInfo, CGRect) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @State private var containerWidth: CGFloat = UIScreen.main.bounds.width

    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var columnsCount: Int { horizontalSizeClass == .regular ? 4 : 2 }

    var body: some View {
        let spacing = UIConstants.Spacing.large
        let horizontalInset = UIConstants.Layout.screenEdgeInset
        let availableWidth = max(1, containerWidth - (horizontalInset * 2))
        let totalSpacing = CGFloat(max(columnsCount - 1, 0)) * spacing
        let cardWidth = floor((availableWidth - totalSpacing) / CGFloat(columnsCount))
        let layout = DeckCardSurfaceLayout(
            cardWidth: cardWidth,
            cardHeight: UIConstants.Size.deckGridCardHeight,
            scale: UIScreen.main.scale,
            isDarkMode: colorScheme == .dark,
            columns: columnsCount
        )
        let placeholderImage = DeckCardSurfaceRenderer.placeholderImage(layout: layout)
        let gridColumns = Array(
            repeating: GridItem(
                .flexible(),
                spacing: spacing,
                alignment: .top
            ),
            count: columnsCount
        )

        Group {
            if cards.isEmpty && !isSelecting {
                emptyState
            } else if !isInitialWarmReady {
                DeckGridWarmupPlaceholder(
                    columns: gridColumns,
                    placeholderImage: placeholderImage
                )
            } else {
                LazyVStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                    ForEach(cards) { section in
                        sectionView(
                            section,
                            columns: gridColumns,
                            placeholderImage: placeholderImage
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Color.clear
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { newWidth in
                    if abs(containerWidth - newWidth) > 0.5 {
                        containerWidth = newWidth
                    }
                }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.bottom, UIConstants.Spacing.standard)
        .task(id: layout.cacheKey) {
            onLayoutResolved(columnsCount, cardWidth)
        }
    }

    @ViewBuilder
    private func sectionView(
        _ section: CardSection,
        columns: [GridItem],
        placeholderImage: UIImage
    ) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            if section.id != "all" {
                sectionHeader(section)
            }

            LazyVGrid(
                columns: columns,
                alignment: .leading,
                spacing: UIConstants.Spacing.large
            ) {
                ForEach(section.cards) { card in
                    DeckGridCardCell(
                        card: card,
                        entry: previewEntryProvider(card),
                        placeholderImage: placeholderImage,
                        isSelecting: isSelecting,
                        isSelected: selectedCards.contains(card.id),
                        accent: accent,
                        onToggleSelection: onToggleSelection,
                        onTapCard: onTapCard,
                        onOpenCardMenu: onOpenCardMenu
                    )
                    .onAppear {
                        onCardVisibilityChanged(card.id, true)
                    }
                    .onDisappear {
                        onCardVisibilityChanged(card.id, false)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ section: CardSection) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            HStack(spacing: UIConstants.Spacing.small) {
                Text(section.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer(minLength: UIConstants.Spacing.small)

                Text("\(section.cards.count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            LinearGradient(
                colors: [
                    Color.primary.opacity(0.12),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
        }
        .padding(.horizontal, UIConstants.Spacing.tiny)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No cards yet")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Tap + to add your first card")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

// =============================================================================
// MARK: - Card Cell
// =============================================================================

private struct DeckGridCardCell: View {
    let card: GridCardInfo
    let entry: DeckCardSurfaceEntry
    let placeholderImage: UIImage
    let isSelecting: Bool
    let isSelected: Bool
    let accent: Color
    let onToggleSelection: (GridCardInfo) -> Void
    let onTapCard: (GridCardInfo) -> Void
    let onOpenCardMenu: (GridCardInfo, CGRect) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var menuAnchorResolver = DeckGridViewFrameResolver()

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
    }

    var body: some View {
        ZStack {
            Image(uiImage: entry.image ?? placeholderImage)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !isSelecting {
                VStack {
                    HStack {
                        Spacer(minLength: 0)
                        menuButton
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, DeckGridCardMetrics.headerTopInset)
                .padding(.trailing, UIConstants.Spacing.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: UIConstants.Size.deckGridCardHeight)
        .clipShape(cardShape)
        .overlay {
            cardShape
                .stroke(borderColor, lineWidth: borderLineWidth)
        }
        .overlay(alignment: .topTrailing) {
            if isSelecting {
                SelectionBubble(isSelected: isSelected, accent: accent)
                    .padding(10)
            }
        }
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.06),
            radius: isSelected ? 10 : 4,
            y: isSelected ? 8 : 3
        )
        .contentShape(cardShape)
        .scaleEffect(isSelecting && isSelected ? 0.94 : 1)
        .animation(.spring(response: UIConstants.Animation.medium, dampingFraction: 0.8), value: isSelected)
        .onTapGesture {
            if isSelecting {
                onToggleSelection(card)
            } else {
                onTapCard(card)
            }
        }
    }

    private var menuButton: some View {
        Button {
            onOpenCardMenu(card, menuAnchorResolver.globalFrame)
        } label: {
            ZStack {
                Color.clear

                Image(systemName: "ellipsis")
                    .font(.system(size: DeckGridCardMetrics.headerMenuIconSize, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.82))
                    .frame(
                        width: DeckGridCardMetrics.headerControlHeight,
                        height: DeckGridCardMetrics.headerControlHeight
                    )
                    .offset(y: -0.5)
            }
            .frame(
                width: DeckGridCardMetrics.headerControlHitSize,
                height: DeckGridCardMetrics.headerControlHitSize
            )
            .contentShape(Rectangle())
            .background(
                DeckGridFrameProbe(resolver: menuAnchorResolver)
            )
        }
        .buttonStyle(.plain)
    }

    private var borderColor: Color {
        if isSelected {
            return accent.opacity(colorScheme == .dark ? 0.75 : 0.55)
        }

        if isSelecting {
            return .clear
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.06)
    }

    private var borderLineWidth: CGFloat {
        isSelected ? 1.5 : (isSelecting ? 0 : 0.75)
    }
}

private struct DeckGridWarmupPlaceholder: View {
    let columns: [GridItem]
    let placeholderImage: UIImage

    private var placeholderCount: Int {
        max(columns.count * 4, 8)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: UIConstants.Spacing.large) {
            ForEach(0..<placeholderCount, id: \.self) { _ in
                Image(uiImage: placeholderImage)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(height: UIConstants.Size.deckGridCardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                            .stroke(Color.primary.opacity(0.05), lineWidth: 0.75)
                    }
            }
        }
    }
}

// =============================================================================
// MARK: - Frame Probe
// =============================================================================

@MainActor
private final class DeckGridViewFrameResolver {
    weak var view: UIView?

    var globalFrame: CGRect {
        guard let view else { return .zero }
        return view.convert(view.bounds, to: nil)
    }
}

private struct DeckGridFrameProbe: UIViewRepresentable {
    let resolver: DeckGridViewFrameResolver

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        resolver.view = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        resolver.view = uiView
    }
}

// =============================================================================
// MARK: - GridCardInfo Presentation Helpers
// =============================================================================

extension GridCardInfo {
    var deckStatusColor: Color {
        if reviewHistoryIsEmpty { return .blue }
        if interval == 0 { return .red }
        if interval >= 14 { return .teal }
        return .orange
    }

    var deckCardLabel: String {
        "Card \(cardNumber)"
    }

    var deckStatusTitle: String {
        if reviewHistoryIsEmpty { return "New" }
        if interval == 0 { return "Due Now" }
        if interval >= 14 { return "Mastered" }
        return "Learning"
    }

    var deckStatusDetail: String {
        if reviewHistoryIsEmpty { return "Never reviewed" }
        if interval == 0 { return "Ready for review" }
        if interval == 1 { return "1 day interval" }
        return "\(interval) day interval"
    }

    var cardMenuSummary: String {
        if isPinned {
            return "\(deckStatusTitle) • \(deckStatusDetail) • Pinned"
        }
        return "\(deckStatusTitle) • \(deckStatusDetail)"
    }
}

// =============================================================================
// MARK: - Zone Helpers
// =============================================================================

nonisolated func getFirstImageData(from zone: ZoneModel) -> Data? {
    if zone.isLeaf {
        guard zone.contentType == .image || zone.contentType == .sketch else { return nil }
        return zone.imageData
    }
    return zone.children?.lazy.compactMap { getFirstImageData(from: $0) }.first
}

nonisolated func containsMedia(_ zone: ZoneModel, contentType: ZoneContentType) -> Bool {
    if zone.isLeaf { return zone.contentType == contentType && zone.imageData != nil }
    return zone.children?.contains { containsMedia($0, contentType: contentType) } ?? false
}

nonisolated func downsample(data: Data, maxDimension: CGFloat) -> UIImage? {
    let options: [CFString: Any] = [
        kCGImageSourceShouldCache: false,
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        kCGImageSourceCreateThumbnailWithTransform: true
    ]

    guard
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else {
        return UIImage(data: data)
    }

    return UIImage(cgImage: cgImage)
}

// =============================================================================
// MARK: - Selection Bubble
// =============================================================================

private struct SelectionBubble: View {
    let isSelected: Bool
    let accent: Color

    var body: some View {
        ZStack {
            if isSelected {
                Circle().fill(accent)
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
            } else {
                Circle().fill(.ultraThinMaterial)
            }
        }
        .frame(width: 26, height: 26)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }
}
