//
//  DeckCardGridView.swift
//  QuizFlash
//
//  iOS 17 Memory Leak — Changes in this file:
//
//  REMOVED: @ModelActor actor CardThumbnailActor
//    The @ModelActor macro was the source of the "zombie" ModelContext that
//    NotificationCenter kept alive after the actor was set to nil.
//
//  REPLACED WITH: CardFetchActor (CardFetchActor.swift)
//    A custom actor with an explicit tearDown() → modelContext.reset() path.
//
//  CardPreviewCache changes:
//    - sharedActor is now CardFetchActor (not CardThumbnailActor)
//    - flushActor() renamed to flush() and now correctly calls actor.tearDown()
//      before releasing the reference (the original version only nil-ed the reference,
//      skipping tearDown — that was a silent bug perpetuating the zombie state)
//    - fetchSnapshot() added: allows DeckViewModel.loadSnapshot to reuse the shared
//      actor rather than spinning up a second background context
//
//  Zone helpers changed from `private` to `internal`:
//    Required so CardFetchActor.generateThumbnail (in a separate file) can call them.
//    All three functions are pure, stateless utilities with no side effects.
//

import SwiftUI
import SwiftData
import UIKit

// =============================================================================
// MARK: - CardPreviewCache
// =============================================================================

/// Thread-safe thumbnail cache backed by NSCache.
/// Owns the shared CardFetchActor and brokers all background SwiftData access.
final class CardPreviewCache {
    static let shared = CardPreviewCache()

    private let cache = NSCache<NSString, CardPreviewPayload>()

    private init() {
        cache.countLimit      = 300
        cache.totalCostLimit  = 20 * 1024 * 1024
    }

    // MARK: - NSCache Access (thread-safe, no actor isolation required)

    func payload(for id: PersistentIdentifier) -> CardPreviewPayload? {
        cache.object(forKey: cacheKey(for: id))
    }

    func store(_ payload: CardPreviewPayload, for id: PersistentIdentifier) {
        let cost = (payload.thumbnailData?.count ?? 0) + 512
        cache.setObject(payload, forKey: cacheKey(for: id), cost: cost)
    }

    func invalidate(for id: PersistentIdentifier) {
        cache.removeObject(forKey: cacheKey(for: id))
    }

    // MARK: - Actor Management (@MainActor isolated to prevent concurrent creation)

    /// The shared background actor. @MainActor ensures the reference is read and written
    /// from a single isolation domain — no lock required.
    @MainActor private var sharedActor: CardFetchActor?

    /// Returns the existing actor or creates one. Always called from the main actor,
    /// so creation is guaranteed to be non-concurrent.
    @MainActor
    private func getOrCreateActor(container: ModelContainer) -> CardFetchActor {
        if let actor = sharedActor { return actor }
        let actor    = CardFetchActor(container: container)
        sharedActor  = actor
        return actor
    }

    // MARK: - Card Snapshot (delegates to CardFetchActor for iOS 17 safe load)

    /// Returns a full card snapshot for the given deck, bypassing the main ModelContext.
    /// Called by DeckViewModel.loadSnapshot — the primary entry point of the iOS 17 fix.
    ///
    /// getOrCreateActor is called without `await` because we are already on the main actor
    /// (this function is @MainActor). The subsequent await hops to CardFetchActor's executor.
    @MainActor
    func fetchSnapshot(deckID: PersistentIdentifier, container: ModelContainer) async -> CardDataSnapshot {
        let actor = getOrCreateActor(container: container)
        return await actor.fetchSnapshot(deckID: deckID)
    }

    // MARK: - Thumbnail Loading (True Lazy — called per visible cell)

    /// Loads or generates a thumbnail payload for a single card.
    ///
    /// Cache hit: returns synchronously from NSCache without any actor hop.
    /// Cache miss: delegates to CardFetchActor.generateThumbnail on the background actor.
    @MainActor
    func loadPayload(for id: PersistentIdentifier, container: ModelContainer) async -> CardPreviewPayload? {
        if let cached = payload(for: id) { return cached }

        let actor = getOrCreateActor(container: container)
        if let generated = await actor.generateThumbnail(for: id) {
            store(generated, for: id)
            return generated
        }
        return nil
    }

    // MARK: - Flush (iOS 17 teardown sequence)

    /// Tears down the shared actor and clears the thumbnail cache.
    /// Must be called on the main actor — from DeckViewModel.tearDown().
    ///
    /// Sequence (order matters for iOS 17):
    ///   1. Capture the actor reference locally (prevents use-after-release).
    ///   2. Nil sharedActor so new callers get a fresh actor immediately.
    ///   3. Clear NSCache (releases UIImage data).
    ///   4. Dispatch actor.tearDown() as a Task — this calls modelContext.reset(),
    ///      which breaks the NotificationCenter retain cycle before ARC deallocs.
    ///
    /// Note: tearDown() is dispatched AFTER nilling sharedActor. This guarantees that
    /// if a new actor is created concurrently (unlikely, but possible), the teardown
    /// of the OLD actor doesn't race with initialization of the new one.
    @MainActor
    func flush() {
        let dying   = sharedActor
        sharedActor = nil
        cache.removeAllObjects()

        if let actor = dying {
            Task { await actor.tearDown() }
        }
    }

    // MARK: - Private Helpers

    private func cacheKey(for id: PersistentIdentifier) -> NSString {
        "\(id.hashValue)" as NSString
    }
}

// =============================================================================
// MARK: - CardPreviewPayload
// =============================================================================

final class CardPreviewPayload: @unchecked Sendable {
    let thumbnailData: Data?
    let hasFrontImage: Bool
    let hasFrontSketch: Bool

    nonisolated init(thumbnailData: Data?, hasFrontImage: Bool, hasFrontSketch: Bool) {
        self.thumbnailData  = thumbnailData
        self.hasFrontImage  = hasFrontImage
        self.hasFrontSketch = hasFrontSketch
    }
}

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
    let isSuspended: Bool

    var onToggleSelection: (GridCardInfo) -> Void
    var onTapCard: (GridCardInfo) -> Void
    var onEditCard: (GridCardInfo) -> Void
    var onConvertCard: (GridCardInfo) -> Void
    var onTogglePinned: (GridCardInfo) -> Void
    var onDeleteCard: (GridCardInfo) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(ThemeManager.self) private var themeManager
    private var accent: Color { themeManager.accentColor.color }
    private var columnsCount: Int { horizontalSizeClass == .regular ? 4 : 2 }
    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(
                .flexible(),
                spacing: UIConstants.Spacing.large,
                alignment: .top
            ),
            count: columnsCount
        )
    }
    private var animationSignature: [String] {
        cards.map { section in
            let cardSignature = section.cards.map { card in
                "\(card.id.hashValue)-\(card.isPinned ? 1 : 0)-\(card.editedAt.timeIntervalSinceReferenceDate)"
            }
            return ([section.id] + cardSignature).joined(separator: "|")
        }
    }
    var body: some View {
        if cards.isEmpty && !isSelecting {
            emptyState
        } else {
            LazyVStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                ForEach(cards) { section in
                    sectionView(section)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: animationSignature)
            .padding(.horizontal, UIConstants.Layout.cardListEdgeInset)
            .padding(.bottom, UIConstants.Spacing.standard)
        }
    }

    @ViewBuilder
    private func cardCell(for card: GridCardInfo) -> some View {
        DeckGridCardCell(
            card: card,
            isSelecting: isSelecting,
            isSelected: selectedCards.contains(card.id),
            isSuspended: isSuspended,
            accent: accent,
            onToggleSelection: onToggleSelection,
            onTapCard: onTapCard,
            onEditCard: onEditCard,
            onConvertCard: onConvertCard,
            onTogglePinned: onTogglePinned,
            onDeleteCard: onDeleteCard
        )
    }

    @ViewBuilder
    private func sectionView(_ section: CardSection) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            if section.id != "all" {
                sectionHeader(section)
            }

            LazyVGrid(
                columns: gridColumns,
                alignment: .leading,
                spacing: UIConstants.Spacing.large
            ) {
                ForEach(section.cards) { card in
                    cardCell(for: card)
                        .transition(.opacity)
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
        .padding(.horizontal, UIConstants.Layout.cardListEdgeInset)
    }

}

enum DeckGridCardMetrics {
    static let headerTopInset: CGFloat = 12
    static let sideInset: CGFloat = 14
    static let statusDotSize: CGFloat = 8
    static let selectionIndicatorSize: CGFloat = 30
}

private struct DeckGridCardCell: View {
    let card: GridCardInfo
    let isSelecting: Bool
    let isSelected: Bool
    let isSuspended: Bool
    let accent: Color
    let onToggleSelection: (GridCardInfo) -> Void
    let onTapCard: (GridCardInfo) -> Void
    let onEditCard: (GridCardInfo) -> Void
    let onConvertCard: (GridCardInfo) -> Void
    let onTogglePinned: (GridCardInfo) -> Void
    let onDeleteCard: (GridCardInfo) -> Void
    @State private var cardSize: CGSize = .zero

    var body: some View {
        if isSelecting || isSuspended {
            cardBody
                .contentShape(RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous))
                .onTapGesture {
                    handleTap()
                }
        } else {
            cardBody
                .contentShape(RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous))
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous))
                .contentShape(.dragPreview, RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous))
                .onTapGesture {
                    handleTap()
                }
                .customContextMenu(
                    id: card.id,
                    isEnabled: !isSelecting && !isSuspended,
                    infoRows: contextMenuInfoRows,
                    actions: contextMenuActions
                ) {
                    contextMenuPreview
                }
        }
    }

    private var contextMenuInfoRows: [CustomContextMenuInfoRow] {
        var rows: [CustomContextMenuInfoRow] = [
            .init(label: "Card", value: "#\(card.cardNumber)"),
            .init(label: "Type", value: card.kindContextMenuTitle),
            .init(label: "Source", value: card.creationSourceContextMenuTitle),
            .init(label: "State", value: card.reviewStateContextMenuTitle),
            .init(label: "Interval", value: card.intervalContextMenuTitle)
        ]

        if card.isPinned {
            rows.append(.init(label: "Pinned", value: "Yes"))
        }

        if card.isConverted {
            rows.append(.init(label: "Converted", value: "Yes"))
        }

        if isSuspended {
            rows.append(.init(label: "Status", value: "Suspended"))
        }

        return rows
    }

    private var contextMenuActions: [CustomContextMenuAction] {
        [
            CustomContextMenuAction(
                title: card.isPinned ? "Unpin" : "Pin",
                systemImage: card.isPinned ? "pin.slash.fill" : "pin.fill",
                role: .normal
            ) {
                onTogglePinned(card)
            },
            CustomContextMenuAction(
                title: "Edit",
                systemImage: "pencil",
                role: .normal
            ) {
                onEditCard(card)
            },
            CustomContextMenuAction(
                title: "Convert",
                systemImage: "arrow.triangle.2.circlepath",
                role: .normal
            ) {
                onConvertCard(card)
            },
            CustomContextMenuAction(
                title: "Delete",
                systemImage: "trash",
                role: .destructive
            ) {
                onDeleteCard(card)
            }
        ]
    }

    private var contextMenuPreview: some View {
        MiniCardPreview(
            card: card,
            isSelected: false,
            isSuspended: isSuspended
        )
        .frame(
            width: cardSize.width > 0 ? cardSize.width : nil,
            height: cardSize.height > 0 ? cardSize.height : nil,
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous))
    }

    private var cardBody: some View {
        MiniCardPreview(
            card: card,
            isSelected: isSelecting && isSelected,
            isSuspended: isSuspended
        )
        .contentShape(RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous))
        .background {
            Color.clear
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { newSize in
                    if abs(cardSize.width - newSize.width) > 0.5 || abs(cardSize.height - newSize.height) > 0.5 {
                        cardSize = newSize
                    }
                }
        }
        .overlay(alignment: .topTrailing) {
            if isSelecting {
                SelectionBubble(
                    isSelected: isSelected,
                    accent: accent,
                    size: DeckGridCardMetrics.selectionIndicatorSize
                )
                    .padding(.top, DeckGridCardMetrics.headerTopInset)
                    .padding(.trailing, DeckGridCardMetrics.sideInset)
                    .allowsHitTesting(false)
            }
        }
        .scaleEffect(isSelecting && isSelected ? 0.9 : 1)
        .animation(.spring(response: 0.24, dampingFraction: 0.88), value: isSelected)
    }

    private func handleTap() {
        if isSelecting {
            onToggleSelection(card)
        } else {
            onTapCard(card)
        }
    }
}

// =============================================================================
// MARK: - MiniCardPreview
// =============================================================================

private struct MiniCardPreview: View {
    let card: GridCardInfo
    var isSelected: Bool = false
    var isSuspended: Bool = false

    @Environment(DevelopmentPreferences.self) private var developmentPreferences
    @Environment(\.colorScheme) private var colorScheme
    @State private var renderedTextSize: CGSize = .zero

    private let titleFontSize: CGFloat = 20
    private let contentPadding = UIConstants.Spacing.medium

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
    }

    private var frontText: String {
        card.frontPreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasFrontText: Bool {
        !frontText.isEmpty
    }

    private var titleText: String {
        if hasFrontText { return frontText }
        let backText = card.backPreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !backText.isEmpty { return backText }
        return "Empty card"
    }

    private var surfaceFill: Color {
        Color(uiColor: colorScheme == .dark ? .secondarySystemGroupedBackground : .secondarySystemBackground)
    }

    var body: some View {
        GeometryReader { proxy in
            let layoutCalculator = MiniCardPreviewLayoutCalculator(
                containerSize: proxy.size,
                contentPadding: contentPadding
            )
            let estimatedTextSize = estimatedTextBlockSize(
                forWidth: layoutCalculator.availableTextWidth
            )
            let textBlockSize = layoutCalculator.resolvedTextBlockSize(
                renderedTextSize: renderedTextSize,
                estimatedTextSize: estimatedTextSize
            )
            let textTopInset = layoutCalculator.centeredTextTopInset(
                textHeight: textBlockSize.height
            )
            let textLeadingInset = layoutCalculator.centeredTextLeadingInset(
                textWidth: textBlockSize.width
            )

            ZStack(alignment: .topLeading) {
                if showsLayoutDebug {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            Color.cyan.opacity(0.9),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                        )
                        .padding(contentPadding)
                        .allowsHitTesting(false)
                }

                if showsLayoutDebug {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            Color.orange.opacity(0.95),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                        )
                        .frame(
                            width: min(max(textBlockSize.width, 1), layoutCalculator.availableTextWidth),
                            height: max(textBlockSize.height, 1),
                            alignment: .topLeading
                        )
                        .padding(.leading, contentPadding)
                        .padding(.top, contentPadding + textTopInset)
                        .offset(x: textLeadingInset)
                        .allowsHitTesting(false)
                }

                titleView
                    .padding(.horizontal, contentPadding)
                    .padding(.top, contentPadding + textTopInset)
                    .offset(x: textLeadingInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: UIConstants.Size.deckGridCardHeight, alignment: .topLeading)
        .background(
            cardShape
                .fill(surfaceFill)
        )
        .clipShape(cardShape)
        .opacity(isSuspended ? 0.72 : 1)
        .contentShape(RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous))
    }

    private var titleView: some View {
        titleTextContent
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                let clampedSize = CGSize(
                    width: ceil(newSize.width),
                    height: ceil(newSize.height)
                )

                if abs(renderedTextSize.width - clampedSize.width) > 0.5
                    || abs(renderedTextSize.height - clampedSize.height) > 0.5 {
                    renderedTextSize = clampedSize
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleTextContent: some View {
        Text(titleText)
            .font(.system(size: titleFontSize, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(6)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var maxTextHeight: CGFloat {
        let font = roundedUIFont(size: titleFontSize, weight: .bold)
        return ceil(font.lineHeight * 6)
    }

    private func estimatedTextBlockSize(forWidth width: CGFloat) -> CGSize {
        let font = roundedUIFont(size: titleFontSize, weight: .bold)
        let label = UILabel()
        label.numberOfLines = 6
        label.lineBreakMode = .byTruncatingTail
        label.font = font
        label.text = titleText

        let fittedSize = label.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )

        return CGSize(
            width: min(ceil(fittedSize.width), width),
            height: min(ceil(fittedSize.height), maxTextHeight)
        )
    }

    private var showsLayoutDebug: Bool {
        AppFeatures.current.showsVisualDebugOverlays
            && developmentPreferences.deckGridTextLayoutDebugEnabled
    }

    private func roundedUIFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let baseFont = UIFont.systemFont(ofSize: size, weight: weight)
        guard
            let descriptor = baseFont.fontDescriptor.withDesign(.rounded)
        else {
            return baseFont
        }

        return UIFont(descriptor: descriptor, size: size)
    }
}

extension GridCardInfo {
    var deckStatusColor: Color {
        if reviewHistoryIsEmpty { return .blue }
        if interval == 0 { return .red }
        if interval >= 14 { return .teal }
        return .orange
    }

    var kindDisplayTitle: String {
        switch kind {
        case .flashcard:
            return "FLASH"
        case .match:
            return "MATCH"
        case .quiz:
            return "QUIZ"
        case .write:
            return "WRITE"
        }
    }

    var kindAccentColor: Color {
        switch kind {
        case .flashcard:
            return .blue
        case .match:
            return .teal
        case .quiz:
            return .orange
        case .write:
            return .green
        }
    }

    var creationSourceDisplayTitle: String {
        switch creationSource {
        case .manual:
            return "MANUAL"
        case .ai:
            return "AI"
        }
    }

    var kindContextMenuTitle: String {
        switch kind {
        case .flashcard:
            return "Flashcard"
        case .match:
            return "Match"
        case .quiz:
            return "Quiz"
        case .write:
            return "Write"
        }
    }

    var creationSourceContextMenuTitle: String {
        switch creationSource {
        case .manual:
            return "Manual"
        case .ai:
            return "AI"
        }
    }

    var reviewStateContextMenuTitle: String {
        if reviewHistoryIsEmpty { return "New" }
        if interval >= 14 { return "Mastered" }
        if interval == 0 { return "Relearning" }
        return "Learning"
    }

    var intervalContextMenuTitle: String {
        if reviewHistoryIsEmpty { return "None" }
        return "\(interval)d"
    }

    var conversionDisplayTitle: String {
        "CONVERTED"
    }

    var conversionAccentColor: Color {
        .teal
    }
}

// =============================================================================
// MARK: - Zone Helpers
//
// Changed from `private` to `internal` so CardFetchActor.generateThumbnail
// (defined in CardFetchActor.swift) can call them from the same module.
// All three are pure, stateless functions with no SwiftData dependencies.
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
        kCGImageSourceShouldCache:                  false,
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize:         maxDimension,
        kCGImageSourceCreateThumbnailWithTransform:  true
    ]
    guard
        let source  = CGImageSourceCreateWithData(data as CFData, nil),
        let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { return UIImage(data: data) }
    return UIImage(cgImage: cgImage)
}

// =============================================================================
// MARK: - SelectionBubble
// =============================================================================

private struct SelectionBubble: View {
    let isSelected: Bool
    let accent: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(isSelected ? 0.08 : 0.05))

            Circle()
                .stroke(
                    isSelected ? accent.opacity(0.85) : Color.white.opacity(0.22),
                    lineWidth: isSelected ? 1.8 : 1.4
                )

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}
