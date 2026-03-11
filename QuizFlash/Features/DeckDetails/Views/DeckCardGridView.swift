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
    var onOpenCardMenu: (GridCardInfo, CGRect) -> Void

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
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
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
            onOpenCardMenu: onOpenCardMenu
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
        .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
    }
}

private enum DeckGridCardMetrics {
    static let headerRowHeight: CGFloat = 20
    static let headerRegionHeight: CGFloat = 23
    static let headerControlHeight: CGFloat = 20
    static let headerControlHitSize: CGFloat = 28
    static let headerMenuIconSize: CGFloat = 10.5
    static let headerTopInset: CGFloat = 6
    static let sideInset: CGFloat = 14
    static let bottomInset: CGFloat = 14
    static let headerTrailingReserve: CGFloat = 30
    static let contentTopPadding: CGFloat = 6
    static let zoneSpacing: CGFloat = 10
    static let separatorWidth: CGFloat = 26
    static let mediaThumbnailSize: CGFloat = 34
    static let mediaBadgeSize: CGFloat = 22
    static let mediaInsetCompensation: CGFloat = 42
    static let statusDotSize: CGFloat = 6
    static let bottomBlurHeight: CGFloat = 44
}

private enum DeckGridCardContentDensity {
    case short
    case standard
    case dense
}

private struct DeckGridCardCell: View {
    let card: GridCardInfo
    let isSelecting: Bool
    let isSelected: Bool
    let isSuspended: Bool
    let accent: Color
    let onToggleSelection: (GridCardInfo) -> Void
    let onTapCard: (GridCardInfo) -> Void
    let onOpenCardMenu: (GridCardInfo, CGRect) -> Void

    var body: some View {
        MiniCardPreview(
            card: card,
            accent: accent,
            isSelected: isSelecting && isSelected,
            isSelectionMode: isSelecting,
            isSuspended: isSuspended,
            onOpenCardMenu: isSelecting ? nil : { frame in
                onOpenCardMenu(card, frame)
            }
        )
        .contentShape(RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if isSelecting {
                SelectionBubble(isSelected: isSelected, accent: accent).padding(10)
            }
        }
        .scaleEffect(isSelecting && isSelected ? 0.9 : 1)
        .animation(.spring(response: UIConstants.Animation.medium, dampingFraction: 0.8), value: isSelected)
        .onTapGesture {
            if isSelecting { onToggleSelection(card) }
            else { onTapCard(card) }
        }
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
    var onOpenCardMenu: ((CGRect) -> Void)? = nil

    @Environment(\.colorScheme)  private var colorScheme
    @Environment(\.modelContext) private var context

    @State private var thumbnail:      UIImage? = nil
    @State private var hasFrontImage:  Bool     = false
    @State private var hasFrontSketch: Bool     = false
    @State private var didLoad:        Bool     = false
    @State private var menuAnchorResolver = DeckGridViewFrameResolver()

    init(
        card: GridCardInfo,
        accent: Color,
        isSelected: Bool = false,
        isSelectionMode: Bool = false,
        isSuspended: Bool = false,
        onOpenCardMenu: ((CGRect) -> Void)? = nil
    ) {
        self.card = card
        self.accent = accent
        self.isSelected = isSelected
        self.isSelectionMode = isSelectionMode
        self.isSuspended = isSuspended
        self.onOpenCardMenu = onOpenCardMenu

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

    private func normalizedPreviewText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.caseInsensitiveCompare("empty") == .orderedSame ? "" : trimmed
    }

    private var frontText: String {
        normalizedPreviewText(card.frontPreviewText)
    }

    private var backText: String {
        normalizedPreviewText(card.backPreviewText)
    }

    private var rawFrontText: String {
        card.frontText
    }

    private var rawBackText: String {
        card.backText
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

    private var primaryTextCharacterCount: Int {
        primaryText.replacingOccurrences(of: "\n", with: " ").count
    }

    private var contentDensity: DeckGridCardContentDensity {
        if primaryTextCharacterCount <= 42 && !primaryText.contains("\n") {
            return .short
        }
        if primaryTextCharacterCount >= 110 || primaryText.contains("\n") {
            return .dense
        }
        return .standard
    }

    private var questionLineLimit: Int {
        if !hasQuestionText {
            return 5
        }
        if !hasAnswerText {
            return contentDensity == .dense ? 6 : 5
        }

        switch contentDensity {
        case .short:
            return 3
        case .standard:
            return 4
        case .dense:
            return 5
        }
    }

    private var questionMaxHeight: CGFloat {
        if !hasQuestionText && hasAnswerText {
            return 112
        }
        if !hasAnswerText {
            return 118
        }

        switch contentDensity {
        case .short:
            return 58
        case .standard:
            return 80
        case .dense:
            return 98
        }
    }

    private var answerLineLimit: Int {
        switch contentDensity {
        case .short:
            return 4
        case .standard:
            return 3
        case .dense:
            return 2
        }
    }

    private var answerMaxHeight: CGFloat {
        switch contentDensity {
        case .short:
            return 60
        case .standard:
            return 48
        case .dense:
            return 38
        }
    }

    private var answerTextColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.84)
            : Color.black.opacity(0.62)
    }

    private var answerTrailingInset: CGFloat {
        hasFooterVisual && !isSuspended ? DeckGridCardMetrics.mediaInsetCompensation : 0
    }

    var body: some View {
        ZStack {
            cardBackground

            GeometryReader { proxy in
                let horizontalInset = DeckGridCardMetrics.sideInset
                let availableWidth = max(0, proxy.size.width - (horizontalInset * 2))
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
                            alignment: .topLeading
                        )
                        .offset(
                            x: horizontalInset,
                            y: DeckGridCardMetrics.headerTopInset
                        )

                    contentZones(availableWidth: availableWidth)
                        .frame(
                            width: availableWidth,
                            height: availableContentHeight,
                            alignment: .topLeading
                        )
                        .offset(x: horizontalInset, y: contentTop)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: UIConstants.Size.deckGridCardHeight)
        .clipShape(cardShape)
        .overlay(alignment: .bottom) {
            bottomContentBlurOverlay
        }
        .overlay {
            cardShape
                .stroke(borderColor, lineWidth: borderLineWidth)
        }
        .overlay(alignment: .bottomTrailing) {
            if hasFooterVisual && !isSuspended {
                mediaOverlay
                    .padding(.trailing, DeckGridCardMetrics.sideInset)
                    .padding(.bottom, DeckGridCardMetrics.bottomInset)
            }
        }
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.08),
            radius: isSelected ? 10 : 4,
            y: isSelected ? 8 : 3
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
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: UIConstants.Spacing.small) {
                headerLeadingContent

                Spacer(minLength: UIConstants.Spacing.small)

                if let _ = onOpenCardMenu, !isSelectionMode {
                    headerMenuButton
                } else {
                    Color.clear
                        .frame(
                            width: DeckGridCardMetrics.headerControlHitSize,
                            height: DeckGridCardMetrics.headerControlHitSize
                        )
                }
            }
            .frame(height: DeckGridCardMetrics.headerRowHeight, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)

            LinearGradient(
                colors: [
                    Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.065),
                    Color.primary.opacity(colorScheme == .dark ? 0.02 : 0.012),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
            .padding(.trailing, DeckGridCardMetrics.headerTrailingReserve)
        }
        .frame(height: DeckGridCardMetrics.headerRegionHeight, alignment: .top)
        .clipped()
    }

    private var headerLeadingContent: some View {
        HStack(spacing: UIConstants.Spacing.small + 2) {
            Circle()
                .fill(card.deckStatusColor)
                .frame(
                    width: DeckGridCardMetrics.statusDotSize,
                    height: DeckGridCardMetrics.statusDotSize
                )

            Text(card.deckCardLabel.uppercased())
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.45)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(height: DeckGridCardMetrics.headerRowHeight, alignment: .center)
    }

    private var headerMenuButton: some View {
        Button {
            guard let onOpenCardMenu else { return }
            onOpenCardMenu(menuAnchorResolver.globalFrame)
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

    private var hasFooterVisual: Bool {
        thumbnail != nil || hasFrontImage || hasFrontSketch
    }

    @ViewBuilder
    private func contentZones(availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            questionZone(availableWidth: availableWidth)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            if hasQuestionText && hasAnswerText {
                Spacer(minLength: DeckGridCardMetrics.zoneSpacing)

                secondaryZone(availableWidth: availableWidth)
                    .frame(maxWidth: .infinity, alignment: .bottomLeading)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func questionZone(availableWidth: CGFloat) -> some View {
        if hasQuestionText {
            previewText(
                fallbackText: frontText,
                richText: rawFrontText,
                needsRichPreview: card.frontNeedsRichSnapshot,
                fontSize: 16.5,
                tone: .question,
                lineLimit: questionLineLimit,
                maxHeight: questionMaxHeight,
                availableWidth: availableWidth,
                side: .front
            )
        } else if hasAnswerText {
            previewText(
                fallbackText: backText,
                richText: rawBackText,
                needsRichPreview: card.backNeedsRichSnapshot,
                fontSize: 15.5,
                tone: .question,
                lineLimit: 5,
                maxHeight: 112,
                availableWidth: availableWidth,
                side: .back
            )
        } else if didLoad && thumbnail == nil {
            emptyPlaceholder
        }
    }

    private func secondaryZone(availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.09))
                .frame(width: DeckGridCardMetrics.separatorWidth, height: 1)
                .padding(.bottom, UIConstants.Spacing.small)

            previewText(
                fallbackText: backText,
                richText: rawBackText,
                needsRichPreview: card.backNeedsRichSnapshot,
                fontSize: 13.5,
                tone: .answer,
                lineLimit: answerLineLimit,
                maxHeight: answerMaxHeight,
                availableWidth: max(0, availableWidth - answerTrailingInset),
                side: .back
            )
            .padding(.trailing, answerTrailingInset)
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

    private func previewText(
        fallbackText: String,
        richText: String,
        needsRichPreview: Bool,
        fontSize: CGFloat,
        tone: DeckGridRichPreviewTone,
        lineLimit: Int,
        maxHeight: CGFloat,
        availableWidth: CGFloat,
        side: DeckGridRichPreviewSide
    ) -> some View {
        DeckGridRichPreviewBlock(
            request: needsRichPreview
                ? DeckGridRichPreviewRequest(
                    cardID: card.id,
                    editedAt: card.editedAt,
                    side: side,
                    text: richText,
                    width: max(1, availableWidth),
                    maxHeight: maxHeight,
                    fontSize: fontSize,
                    tone: tone,
                    colorScheme: colorScheme
                )
                : nil,
            fallbackText: fallbackText,
            fontSize: fontSize,
            textColor: tone == .question ? .primary : answerTextColor,
            lineLimit: lineLimit,
            maxHeight: maxHeight,
            availableWidth: availableWidth,
            colorScheme: colorScheme,
            isSuspended: isSuspended
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: maxHeight, alignment: .topLeading)
        .clipped()
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

    private var bottomContentBlurOverlay: some View {
        LinearGradient(
            colors: [
                .clear,
                Color(uiColor: .secondarySystemGroupedBackground).opacity(colorScheme == .dark ? 0.16 : 0.05),
                Color(uiColor: .secondarySystemGroupedBackground).opacity(colorScheme == .dark ? 0.42 : 0.12)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: DeckGridCardMetrics.bottomBlurHeight)
        .clipShape(cardShape)
        .allowsHitTesting(false)
    }

    private var cardBackground: some View {
        let base = colorScheme == .dark
            ? Color(uiColor: .secondarySystemGroupedBackground)
            : Color.white
        let topHighlight = Color.white.opacity(colorScheme == .dark ? 0.028 : 0.30)
        let bottomGlowColor = colorScheme == .dark
            ? Color.white.opacity(0.030)
            : Color.black.opacity(0.010)
        let bottomVignette = Color.black.opacity(colorScheme == .dark ? 0.08 : 0.018)

        return ZStack {
            cardShape
                .fill(base)

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

            Ellipse()
                .fill(bottomGlowColor)
                .frame(width: 148, height: 44)
                .blur(radius: 20)
                .offset(x: 0, y: 108)

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

    private var borderColor: Color {
        if isSelected {
            return accent.opacity(colorScheme == .dark ? 0.75 : 0.55)
        }

        if isSelectionMode {
            return .clear
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.06)
    }

    private var borderLineWidth: CGFloat {
        isSelected ? 1.5 : (isSelectionMode ? 0 : 0.75)
    }
}

private struct DeckGridRichPreviewBlock: View {
    let request: DeckGridRichPreviewRequest?
    let fallbackText: String
    let fontSize: CGFloat
    let textColor: Color
    let lineLimit: Int
    let maxHeight: CGFloat
    let availableWidth: CGFloat
    let colorScheme: ColorScheme
    let isSuspended: Bool

    @State private var snapshot: UIImage? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            fallbackBody
                .opacity(snapshot == nil ? 1 : 0.001)

            if let snapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(
                        width: snapshot.size.width,
                        height: snapshot.size.height,
                        alignment: .topLeading
                    )
            }
        }
        .task(id: "\(request?.cacheKey ?? "")-\(isSuspended ? 1 : 0)") {
            guard let request, !isSuspended else {
                snapshot = nil
                return
            }

            let cached = await MainActor.run {
                DeckGridRichPreviewCache.shared.image(for: request)
            }
            if let cached {
                snapshot = cached
                return
            }

            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled, !isSuspended else { return }

            if let rendered = await DeckGridRichPreviewRenderer.shared.image(for: request),
               !Task.isCancelled,
               !isSuspended {
                snapshot = rendered
            }
        }
        .onChange(of: isSuspended) { _, suspended in
            if suspended {
                snapshot = nil
            }
        }
        .onDisappear {
            snapshot = nil
        }
    }

    private var fallbackBody: some View {
        DeckGridFormattedFallbackText(
            text: fallbackText,
            fontSize: fontSize,
            textColor: textColor,
            lineLimit: lineLimit,
            maxHeight: maxHeight,
            availableWidth: availableWidth,
            colorScheme: colorScheme
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: maxHeight, alignment: .topLeading)
        .clipped()
    }
}

private struct DeckGridFormattedFallbackText: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let textColor: Color
    let lineLimit: Int
    let maxHeight: CGFloat
    let availableWidth: CGFloat
    let colorScheme: ColorScheme

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.backgroundColor = .clear
        label.numberOfLines = lineLimit
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ uiView: UILabel, context: Context) {
        uiView.numberOfLines = lineLimit
        uiView.preferredMaxLayoutWidth = max(1, availableWidth)
        uiView.attributedText = DeckGridFormattedFallbackBuilder.make(
            text: text,
            fontSize: fontSize,
            textColor: UIColor(textColor),
            colorScheme: colorScheme
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let width = max(1, proposal.width ?? availableWidth)
        let fitted = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: min(maxHeight, fitted.height))
    }
}

private enum DeckGridFormattedFallbackBuilder {
    private enum Segment {
        case plain(String)
        case strong(String)
        case code(String)
    }

    static func make(
        text: String,
        fontSize: CGFloat,
        textColor: UIColor,
        colorScheme: ColorScheme
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let segments = parse(text)

        for segment in segments {
            let fragment: NSAttributedString

            switch segment {
            case .plain(let value):
                fragment = NSAttributedString(
                    string: value,
                    attributes: baseAttributes(fontSize: fontSize, textColor: textColor)
                )

            case .strong(let value):
                fragment = NSAttributedString(
                    string: value,
                    attributes: strongAttributes(fontSize: fontSize, textColor: textColor)
                )

            case .code(let value):
                fragment = NSAttributedString(
                    string: MathTextSanitizer.normalizedCodeLiteral(value),
                    attributes: codeAttributes(
                        fontSize: fontSize,
                        textColor: textColor,
                        colorScheme: colorScheme
                    )
                )
            }

            result.append(fragment)
        }

        if result.length == 0 {
            return NSAttributedString(
                string: text,
                attributes: baseAttributes(fontSize: fontSize, textColor: textColor)
            )
        }

        return result
    }

    private static func parse(_ text: String) -> [Segment] {
        var segments: [Segment] = []
        var buffer = ""
        var cursor = text.startIndex

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            segments.append(.plain(buffer))
            buffer.removeAll(keepingCapacity: true)
        }

        while cursor < text.endIndex {
            if text[cursor] == "`",
               let closing = text[text.index(after: cursor)...].firstIndex(of: "`") {
                flushBuffer()
                let inner = String(text[text.index(after: cursor)..<closing])
                segments.append(.code(inner))
                cursor = text.index(after: closing)
                continue
            }

            if text[cursor...].hasPrefix("**") {
                let contentStart = text.index(cursor, offsetBy: 2)
                if let closing = text[contentStart...].range(of: "**") {
                    flushBuffer()
                    let inner = String(text[contentStart..<closing.lowerBound])
                    segments.append(.strong(inner))
                    cursor = closing.upperBound
                    continue
                }
            }

            buffer.append(text[cursor])
            cursor = text.index(after: cursor)
        }

        flushBuffer()
        return segments
    }

    private static func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func paragraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }

    private static func baseAttributes(fontSize: CGFloat, textColor: UIColor) -> [NSAttributedString.Key: Any] {
        [
            .font: roundedFont(size: fontSize, weight: .regular),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle()
        ]
    }

    private static func strongAttributes(fontSize: CGFloat, textColor: UIColor) -> [NSAttributedString.Key: Any] {
        [
            .font: roundedFont(size: fontSize, weight: .bold),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle()
        ]
    }

    private static func codeAttributes(
        fontSize: CGFloat,
        textColor: UIColor,
        colorScheme: ColorScheme
    ) -> [NSAttributedString.Key: Any] {
        let background = colorScheme == .dark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor.black.withAlphaComponent(0.06)
        let foreground = colorScheme == .dark
            ? UIColor.white.withAlphaComponent(0.94)
            : textColor.withAlphaComponent(0.9)

        return [
            .font: UIFont.monospacedSystemFont(ofSize: max(11, fontSize * 0.9), weight: .semibold),
            .foregroundColor: foreground,
            .backgroundColor: background,
            .paragraphStyle: paragraphStyle()
        ]
    }
}

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

extension GridCardInfo {
    /// Semantic status tint shared by the deck card grid and the card context menu.
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

    var body: some View {
        ZStack {
            if isSelected {
                Circle().fill(accent)
                Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(.white)
            } else {
                Circle().fill(.ultraThinMaterial)
            }
        }
        .frame(width: 26, height: 26)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }
}
