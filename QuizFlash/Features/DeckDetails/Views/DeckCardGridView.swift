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

    var onToggleSelection: (GridCardInfo) -> Void
    var onTapCard: (GridCardInfo) -> Void
    var onOpenCardMenu: (GridCardInfo, CGRect) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var columnsCount: Int { horizontalSizeClass == .regular ? 4 : 2 }

    var body: some View {
        if cards.isEmpty && !isSelecting {
            emptyState
        } else {
            LazyVStack(spacing: 0) {
                ForEach(cards) { section in
                    if section.id != "all" {
                        Text(section.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 16)
                            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
                    }

                    let chunks = section.cards.chunked(into: columnsCount)
                    ForEach(chunks.indices, id: \.self) { rowIndex in
                        HStack(spacing: 16) {
                            ForEach(chunks[rowIndex]) { card in
                                cardCell(for: card)
                                    .id(card.id)
                            }
                            let remaining = columnsCount - chunks[rowIndex].count
                            if remaining > 0 {
                                ForEach(0..<remaining, id: \.self) { _ in
                                    Color.clear.frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cardCell(for card: GridCardInfo) -> some View {
        DeckGridCardCell(
            card: card,
            isSelecting: isSelecting,
            isSelected: selectedCards.contains(card.id),
            accent: accent,
            onToggleSelection: onToggleSelection,
            onTapCard: onTapCard,
            onOpenCardMenu: onOpenCardMenu
        )
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

private struct DeckGridCardCell: View {
    let card: GridCardInfo
    let isSelecting: Bool
    let isSelected: Bool
    let accent: Color
    let onToggleSelection: (GridCardInfo) -> Void
    let onTapCard: (GridCardInfo) -> Void
    let onOpenCardMenu: (GridCardInfo, CGRect) -> Void

    @State private var cardFrame: CGRect = .zero
    @State private var optionsButtonFrame: CGRect = .zero

    var body: some View {
        MiniCardPreview(
            card: card,
            isSelected: isSelecting && isSelected,
            isSelectionMode: isSelecting
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if isSelecting {
                SelectionBubble(isSelected: isSelected, accent: accent).padding(10)
            } else {
                optionsButton
                    .padding(10)
            }
        }
        .scaleEffect(isSelecting && isSelected ? 0.9 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        .onTapGesture {
            if isSelecting { onToggleSelection(card) }
            else { onTapCard(card) }
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { newValue in
            cardFrame = newValue
        }
    }

    private var optionsButton: some View {
        Button {
            onOpenCardMenu(card, resolvedAnchorFrame)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.88))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { newValue in
            optionsButtonFrame = newValue
        }
    }

    private var resolvedAnchorFrame: CGRect {
        optionsButtonFrame == .zero ? cardFrame : optionsButtonFrame
    }
}

// =============================================================================
// MARK: - MiniCardPreview
// =============================================================================

private struct MiniCardPreview: View {
    let card: GridCardInfo
    var isSelected: Bool = false
    var isSelectionMode: Bool = false

    @Environment(\.colorScheme)  private var colorScheme
    @Environment(\.modelContext) private var context

    @State private var thumbnail:      UIImage? = nil
    @State private var hasFrontImage:  Bool     = false
    @State private var hasFrontSketch: Bool     = false
    @State private var didLoad:        Bool     = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow

            questionPreview
            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if hasFrontImage  { Image(systemName: "photo").font(.caption2) }
                if hasFrontSketch { Image(systemName: "scribble.variable").font(.caption2) }
                Spacer()
            }
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: UIConstants.Size.deckGridCardHeight)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            if !isSelectionMode {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(borderColor, lineWidth: 0.5)
            }
        }
        // True lazy loading: thumbnail is requested only when the cell becomes visible.
        // task(id:) cancels automatically when the cell scrolls off screen, preventing
        // wasted work for rapidly-scrolled cells.
        .task(id: card.id) {
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
        // Release the decoded image when the cell leaves the viewport.
        // NSCache retains the compressed Data; only the UIImage is freed here,
        // recovering the decoded pixel buffer memory (~4 bytes/pixel uncompressed).
        .onDisappear {
            thumbnail = nil
        }
    }

    @ViewBuilder
    private var questionPreview: some View {
        let frontText = card.frontText.trimmingCharacters(in: .whitespacesAndNewlines)
        let backText = card.backText.trimmingCharacters(in: .whitespacesAndNewlines)

        VStack(alignment: .leading, spacing: 6) {
            if !frontText.isEmpty {
                Text(frontText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(backText.isEmpty ? 7 : 5)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.8)
            }

            if !backText.isEmpty {
                Text(backText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(frontText.isEmpty ? 6 : 4)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.82)
            }

            if frontText.isEmpty && backText.isEmpty && didLoad && thumbnail == nil {
                Text("Empty card")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            if let img = thumbnail {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(card.deckStatusColor)
                    .frame(width: 7, height: 7)

                Text("\(card.cardNumber)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(card.deckStatusColor.opacity(0.13), in: Capsule())

            if card.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(card.deckStatusColor)
                    .padding(.leading, 2)
            }

            Spacer()
        }
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
        let base = colorScheme == .dark
            ? Color(uiColor: .secondarySystemGroupedBackground)
            : Color.white

        return RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(base)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.06)
    }
}

extension GridCardInfo {
    var deckStatusColor: Color {
        if reviewHistoryIsEmpty { return .blue }
        if interval == 0 { return .red }
        if interval >= 14 { return .teal }
        return .orange
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

// =============================================================================
// MARK: - Array + chunked
// =============================================================================

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
