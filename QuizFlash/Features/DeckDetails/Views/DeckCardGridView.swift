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
    let activeActionMenuCardID: PersistentIdentifier?

    var onToggleSelection: (GridCardInfo) -> Void
    var onTapCard: (GridCardInfo) -> Void
    var onEditCard: (GridCardInfo) -> Void
    var onConvertCard: (GridCardInfo) -> Void
    var onTogglePinned: (GridCardInfo) -> Void
    var onDeleteCard: (GridCardInfo) -> Void
    var onPresentActionMenu: (PersistentIdentifier) -> Void
    var onDismissActionMenu: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var accent: Color { ThemeManager.shared.accentColor.color }
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
            .onChange(of: isSelecting) { _, selecting in
                guard selecting else { return }
                onDismissActionMenu()
            }
            .onChange(of: isSuspended) { _, suspended in
                guard suspended else { return }
                onDismissActionMenu()
            }
        }
    }

    @ViewBuilder
    private func cardCell(for card: GridCardInfo) -> some View {
        DeckGridCardCell(
            card: card,
            isSelecting: isSelecting,
            isSelected: selectedCards.contains(card.id),
            isSuspended: isSuspended,
            isActionMenuPresented: activeActionMenuCardID == card.id,
            accent: accent,
            onToggleSelection: onToggleSelection,
            onTapCard: onTapCard,
            onEditCard: onEditCard,
            onConvertCard: onConvertCard,
            onTogglePinned: onTogglePinned,
            onDeleteCard: onDeleteCard,
            onPresentActionMenu: { onPresentActionMenu(card.id) },
            onDismissActionMenu: onDismissActionMenu
        )
        .anchorPreference(key: DeckGridCardBoundsPreferenceKey.self, value: .bounds) {
            [card.id: $0]
        }
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

struct DeckGridCardBoundsPreferenceKey: PreferenceKey {
    static var defaultValue: [PersistentIdentifier: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [PersistentIdentifier: Anchor<CGRect>],
        nextValue: () -> [PersistentIdentifier: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

enum DeckGridCardMetrics {
    static let headerRegionHeight: CGFloat = 22
    static let headerTopInset: CGFloat = 8
    static let sideInset: CGFloat = 18
    static let bottomInset: CGFloat = 16
    static let contentTopPadding: CGFloat = 2
    static let mediaThumbnailSize: CGFloat = 34
    static let mediaBadgeSize: CGFloat = 22
    static let mediaInsetCompensation: CGFloat = 42
    static let statusDotSize: CGFloat = 6
    static let selectionIndicatorSize: CGFloat = 30
    static let headerMenuHeight: CGFloat = 48
    static let headerMenuSpacing: CGFloat = 12
    static let headerMenuFloatingGap: CGFloat = 8
    static let overflowIndicatorBottomInset: CGFloat = 2
}

private struct DeckGridCardCell: View {
    let card: GridCardInfo
    let isSelecting: Bool
    let isSelected: Bool
    let isSuspended: Bool
    let isActionMenuPresented: Bool
    let accent: Color
    let onToggleSelection: (GridCardInfo) -> Void
    let onTapCard: (GridCardInfo) -> Void
    let onEditCard: (GridCardInfo) -> Void
    let onConvertCard: (GridCardInfo) -> Void
    let onTogglePinned: (GridCardInfo) -> Void
    let onDeleteCard: (GridCardInfo) -> Void
    let onPresentActionMenu: () -> Void
    let onDismissActionMenu: () -> Void
    @State private var isPressingForMenu = false
    @State private var pendingMenuPressFeedback: DispatchWorkItem?

    var body: some View {
        cardBody
        .contentShape(RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous))
        .onTapGesture {
            handleTap()
        }
        .onLongPressGesture(
            minimumDuration: 0.55,
            maximumDistance: 10,
            perform: {
                guard !(isSelecting || isSuspended) else { return }
                cancelPendingPressFeedback()
                resetPressFeedback()
                onPresentActionMenu()
            },
            onPressingChanged: { pressing in
                guard !(isSelecting || isSuspended) else {
                    resetPressFeedback()
                    return
                }
                if pressing {
                    schedulePressFeedbackIfNeeded()
                } else {
                    resetPressFeedback()
                }
            }
        )
        .onChange(of: isActionMenuPresented) { _, presented in
            if presented {
                resetPressFeedback()
            }
        }
        .onDisappear {
            resetPressFeedback()
        }
    }

    private var cardScale: CGFloat {
        if isSelecting && isSelected { return 0.9 }
        if isActionMenuPresented { return 0.89 }
        if isPressingForMenu { return 0.89 }
        return 1
    }

    private var cardAnimation: Animation {
        if isPressingForMenu {
            return menuPressAnimation
        }
        return .spring(response: 0.24, dampingFraction: 0.88)
    }

    private var menuPressAnimation: Animation {
        .timingCurve(0.18, 0.86, 0.24, 1.0, duration: 0.3)
    }

    private var cardBody: some View {
        MiniCardPreview(
            card: card,
            accent: accent,
            isSelected: isSelecting && isSelected,
            isSelectionMode: isSelecting,
            isSuspended: isSuspended,
            isActionMenuPresented: isActionMenuPresented
        )
        .contentShape(RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous))
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
        .scaleEffect(cardScale)
        .animation(cardAnimation, value: isSelected)
        .animation(cardAnimation, value: isPressingForMenu)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isActionMenuPresented)
    }

    private func handleTap() {
        resetPressFeedback()
        if isActionMenuPresented {
            onDismissActionMenu()
            return
        }
        if isSelecting {
            onToggleSelection(card)
        } else {
            onTapCard(card)
        }
    }

    private func resetPressFeedback() {
        cancelPendingPressFeedback()
        if isPressingForMenu {
            withAnimation(.easeOut(duration: 0.14)) {
                isPressingForMenu = false
            }
        } else {
            isPressingForMenu = false
        }
    }

    private func schedulePressFeedbackIfNeeded() {
        cancelPendingPressFeedback()
        guard !isActionMenuPresented else { return }

        let workItem = DispatchWorkItem {
            withAnimation(menuPressAnimation) {
                isPressingForMenu = true
            }
        }
        pendingMenuPressFeedback = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func cancelPendingPressFeedback() {
        pendingMenuPressFeedback?.cancel()
        pendingMenuPressFeedback = nil
    }
}

// =============================================================================
// MARK: - MiniCardPreview
// =============================================================================

private struct MiniCardPreview: View {
    let card: GridCardInfo
    let accent: Color
    var isSelected: Bool = false
    var isSelectionMode: Bool = false
    var isSuspended: Bool = false
    var isActionMenuPresented: Bool = false

    @Environment(\.colorScheme)  private var colorScheme
    @Environment(\.modelContext) private var context

    @State private var thumbnail:      UIImage? = nil
    @State private var hasFrontImage:  Bool     = false
    @State private var hasFrontSketch: Bool     = false
    @State private var didLoad:        Bool     = false

    init(
        card: GridCardInfo,
        accent: Color,
        isSelected: Bool = false,
        isSelectionMode: Bool = false,
        isSuspended: Bool = false,
        isActionMenuPresented: Bool = false
    ) {
        self.card = card
        self.accent = accent
        self.isSelected = isSelected
        self.isSelectionMode = isSelectionMode
        self.isSuspended = isSuspended
        self.isActionMenuPresented = isActionMenuPresented

        let initialPayload = CardPreviewCache.shared.payload(for: card.id)
        _thumbnail = State(initialValue: initialPayload.flatMap { payload in
            payload.thumbnailData.flatMap(UIImage.init(data:))
        })
        _hasFrontImage = State(initialValue: initialPayload?.hasFrontImage ?? false)
        _hasFrontSketch = State(initialValue: initialPayload?.hasFrontSketch ?? false)
        _didLoad = State(initialValue: initialPayload != nil)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
    }

    private var frontText: String {
        card.frontPreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var backText: String {
        card.backPreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasQuestionText: Bool {
        !frontText.isEmpty
    }

    private var hasAnswerText: Bool {
        !backText.isEmpty
    }

    private var primaryText: String {
        hasQuestionText ? frontText : backText
    }

    private var primaryTrailingInset: CGFloat {
        hasFooterVisual && !isSuspended ? DeckGridCardMetrics.mediaInsetCompensation : 0
    }

    var body: some View {
        ZStack {
            cardBackground

            GeometryReader { proxy in
                let horizontalInset = DeckGridCardMetrics.sideInset
                let availableWidth = max(0, proxy.size.width - (horizontalInset * 2))
                let contentWidth = max(0, availableWidth - primaryTrailingInset)
                let contentTop = DeckGridCardMetrics.headerTopInset
                    + DeckGridCardMetrics.headerRegionHeight
                    + DeckGridCardMetrics.contentTopPadding
                let availableContentHeight = max(
                    0,
                    proxy.size.height - contentTop - DeckGridCardMetrics.bottomInset
                )

                ZStack(alignment: .topLeading) {
                    topBar
                .frame(
                    width: availableWidth,
                    height: DeckGridCardMetrics.headerRegionHeight,
                    alignment: .leading
                )
                .offset(
                    x: horizontalInset,
                    y: DeckGridCardMetrics.headerTopInset
                        )

                    contentZones(
                        availableHeight: availableContentHeight,
                        contentWidth: contentWidth
                    )
                        .frame(
                            width: availableWidth,
                            height: availableContentHeight,
                            alignment: .center
                        )
                        .offset(x: horizontalInset, y: contentTop)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: UIConstants.Size.deckGridCardHeight)
        .widgetStyle(cornerRadius: UIConstants.Radius.large)
        .overlay(alignment: .bottomTrailing) {
            if hasFooterVisual && !isSuspended {
                mediaOverlay
                    .padding(.trailing, DeckGridCardMetrics.sideInset)
                    .padding(.bottom, DeckGridCardMetrics.bottomInset)
            }
        }
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.08),
            radius: isActionMenuPresented ? 14 : (isSelected ? 6 : 4),
            y: isActionMenuPresented ? 8 : (isSelected ? 5 : 3)
        )
        .task(id: "\(card.id.hashValue)-\(isSuspended ? 1 : 0)") {
            guard !isSuspended else {
                thumbnail = nil
                hasFrontImage = false
                hasFrontSketch = false
                didLoad = false
                return
            }
            if let cached = CardPreviewCache.shared.payload(for: card.id) {
                applyPayload(cached)
                return
            }
            if let payload = await CardPreviewCache.shared.loadPayload(
                for: card.id,
                container: context.container
            ) {
                await MainActor.run { applyPayload(payload) }
            } else {
                await MainActor.run { didLoad = true }
            }
        }
        .onChange(of: isSuspended) { _, suspended in
            guard suspended else { return }
            thumbnail = nil
            hasFrontImage = false
            hasFrontSketch = false
        }
        // Release the decoded image when the cell leaves the viewport.
        // NSCache retains the compressed Data; only the UIImage is freed here,
        // recovering the decoded pixel buffer memory (~4 bytes/pixel uncompressed).
        .onDisappear {
            thumbnail = nil
        }
        .contentShape(RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous))
    }

    private var topBar: some View {
        normalHeader
        .frame(height: DeckGridCardMetrics.headerRegionHeight, alignment: .center)
    }

    private var normalHeader: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(card.deckStatusColor)
                .frame(
                    width: DeckGridCardMetrics.statusDotSize,
                    height: DeckGridCardMetrics.statusDotSize
                )

            Text("\(card.cardNumber)")
                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)

            Text(card.kindDisplayTitle)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(card.kindAccentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(card.kindAccentColor.opacity(0.12), in: Capsule())

            if card.isConverted {
                Text(card.conversionDisplayTitle)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(card.conversionAccentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(card.conversionAccentColor.opacity(0.12), in: Capsule())
            }

            Text(card.creationSourceDisplayTitle)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(card.creationSourceAccentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(card.creationSourceAccentColor.opacity(0.12), in: Capsule())

            Spacer(minLength: 0)
        }
    }

    private var hasFooterVisual: Bool {
        thumbnail != nil || hasFrontImage || hasFrontSketch
    }

    @ViewBuilder
    private func contentZones(
        availableHeight: CGFloat,
        contentWidth: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            primaryZone(
                availableHeight: availableHeight,
                contentWidth: contentWidth
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func primaryZone(
        availableHeight: CGFloat,
        contentWidth: CGFloat
    ) -> some View {
        if !primaryText.isEmpty {
            OverflowFadedDeckText(
                text: primaryText,
                fontSize: hasQuestionText ? 18 : 16.5,
                textColor: .primary,
                width: contentWidth,
                maxHeight: availableHeight
            )
            .frame(width: contentWidth, alignment: .leading)
        } else if didLoad && thumbnail == nil {
            emptyPlaceholder
        }
    }

    private var emptyPlaceholder: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.tiny) {
            Text("Empty card")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text("Add text, math, or media.")
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var mediaOverlay: some View {
        if let img = thumbnail {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(
                    width: DeckGridCardMetrics.mediaThumbnailSize,
                    height: DeckGridCardMetrics.mediaThumbnailSize
                )
                .clipShape(RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.58), lineWidth: 0.75)
                }
        } else {
            HStack(spacing: UIConstants.Spacing.tiny) {
                if hasFrontImage {
                    mediaBadge(symbol: "photo")
                }
                if hasFrontSketch {
                    mediaBadge(symbol: "scribble.variable")
                }
            }
        }
    }

    private func mediaBadge(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(
                width: DeckGridCardMetrics.mediaBadgeSize,
                height: DeckGridCardMetrics.mediaBadgeSize
            )
            .background(
                Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.045),
                in: RoundedRectangle(cornerRadius: UIConstants.Radius.small, style: .continuous)
            )
    }

    private func applyPayload(_ payload: CardPreviewPayload) {
        hasFrontImage  = payload.hasFrontImage
        hasFrontSketch = payload.hasFrontSketch
        didLoad        = true
        if let data = payload.thumbnailData {
            thumbnail = UIImage(data: data)
        }
    }

    private var cardBackground: some View {
        let topHighlight = Color.white.opacity(colorScheme == .dark ? 0.026 : 0.18)
        let bottomVignette = Color.black.opacity(colorScheme == .dark ? 0.05 : 0.012)

        return ZStack {
            cardShape
                .fill(
                    LinearGradient(
                        colors: [
                            topHighlight,
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )

            cardShape
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            .clear,
                            bottomVignette
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
}

struct DeckGridHeaderActionMenu: View {
    let isPinned: Bool
    let accent: Color
    let onTogglePinned: () -> Void
    let onEdit: () -> Void
    let onConvert: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: DeckGridCardMetrics.headerMenuSpacing) {
            actionButton(
                symbol: isPinned ? "pin.slash.fill" : "pin.fill",
                tint: .primary,
                action: onTogglePinned
            )

            actionButton(
                symbol: "pencil",
                tint: accent,
                action: onEdit
            )

            actionButton(
                symbol: "arrow.triangle.2.circlepath",
                tint: accent,
                action: onConvert
            )

            actionButton(
                symbol: "trash",
                tint: .red,
                action: onDelete
            )
        }
        .padding(.horizontal, 14)
        .frame(height: DeckGridCardMetrics.headerMenuHeight)
        .glassButton(shape: .capsule)
    }

    private func actionButton(
        symbol: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct OverflowFadedDeckText: View {
    let text: String
    let fontSize: CGFloat
    let textColor: Color
    let width: CGFloat
    let maxHeight: CGFloat

    @State private var measuredHeight: CGFloat = 0

    private var textView: some View {
        Text(verbatim: text)
            .font(.system(size: fontSize, weight: .medium, design: .rounded))
            .foregroundStyle(textColor)
            .multilineTextAlignment(.leading)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isOverflowing: Bool {
        measuredHeight > maxHeight + 1
    }

    private var estimatedLineHeight: CGFloat {
        fontSize + 6
    }

    private var visibleLineCount: Int {
        max(2, Int(maxHeight / estimatedLineHeight))
    }

    var body: some View {
        textView
            .frame(width: width, alignment: .leading)
            .frame(maxHeight: maxHeight, alignment: .center)
            .lineLimit(visibleLineCount)
            .truncationMode(.tail)
            .clipped()
            .background(alignment: .topLeading) {
                textView
                    .frame(width: width, alignment: .leading)
                    .hidden()
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear {
                                    measuredHeight = proxy.size.height
                                }
                                .onChange(of: proxy.size.height) { _, newHeight in
                                    measuredHeight = newHeight
                                }
                        }
                    }
            }
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

    var creationSourceAccentColor: Color {
        switch creationSource {
        case .manual:
            return .secondary
        case .ai:
            return ThemeManager.shared.accentColor.color
        }
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
