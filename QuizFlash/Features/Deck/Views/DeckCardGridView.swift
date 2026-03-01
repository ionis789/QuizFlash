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

    init(thumbnailData: Data?, hasFrontImage: Bool, hasFrontSketch: Bool) {
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
    var onLongPressCard: (GridCardInfo) -> Void
    var onDeleteCard: (GridCardInfo) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var columnsCount: Int { horizontalSizeClass == .regular ? 4 : 2 }

    var body: some View {
        if cards.isEmpty && !isSelecting {
            emptyState
        } else {
            ForEach(cards) { section in
                if section.id != "all" {
                    Text(section.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 16)
                        .padding(.horizontal, 20)
                }

                let chunks = section.cards.chunked(into: columnsCount)
                ForEach(chunks.indices, id: \.self) { rowIndex in
                    HStack(spacing: 16) {
                        ForEach(chunks[rowIndex]) { card in
                            cardCell(for: card)
                                .id(card.id) // ✅ FIX CRITIC: Restore scroll position
                        }
                        let remaining = columnsCount - chunks[rowIndex].count
                        if remaining > 0 {
                            ForEach(0..<remaining, id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    @ViewBuilder
    private func cardCell(for card: GridCardInfo) -> some View {
        let isSelected = selectedCards.contains(card.id)

        Button {
            if isSelecting { onToggleSelection(card) }
            else           { onTapCard(card) }
        } label: {
            MiniCardPreview(card: card, isSelected: isSelecting && isSelected)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if isSelecting {
                SelectionBubble(isSelected: isSelected, accent: accent).padding(10)
            }
        }
        .scaleEffect(isSelecting && isSelected ? 0.9 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        .contextMenu {
            if !isSelecting {
                Button { onLongPressCard(card) } label: { Label("Edit",   systemImage: "pencil") }
                Button(role: .destructive) { onDeleteCard(card) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            if !isSelecting { onLongPressCard(card) }
        }
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
        .padding(.horizontal, 20)
    }
}

// =============================================================================
// MARK: - MiniCardPreview
// =============================================================================

private struct MiniCardPreview: View {
    let card: GridCardInfo
    var isSelected: Bool = false

    @Environment(\.colorScheme)  private var colorScheme
    @Environment(\.modelContext) private var context
    private var accent: Color { ThemeManager.shared.accentColor.color }

    @State private var thumbnail:      UIImage? = nil
    @State private var hasFrontImage:  Bool     = false
    @State private var hasFrontSketch: Bool     = false
    @State private var didLoad:        Bool     = false

    private var cardStatus: (color: Color, icon: String, label: String) {
        if card.reviewHistoryIsEmpty { return (.blue,   "sparkles",                       "New")      }
        if card.interval == 0        { return (.red,    "arrow.triangle.2.circlepath",    "Review")   }
        if card.interval >= 14       { return (.teal,   "checkmark.seal.fill",            "Mastered") }
        return                               (.orange, "flame.fill",                     "Learning")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Card number + status badge row
            HStack {
                Text("#\(card.cardNumber)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: cardStatus.icon)
                    Text(cardStatus.label)
                }
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(cardStatus.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(cardStatus.color.opacity(0.15), in: Capsule())
            }

            questionPreview
            Spacer(minLength: 0)

            // Media indicator icons
            HStack(spacing: 6) {
                if hasFrontImage  { Image(systemName: "photo").font(.caption2) }
                if hasFrontSketch { Image(systemName: "scribble.variable").font(.caption2) }
                Spacer()
            }
            .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 140)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? .gray : borderColor, lineWidth: isSelected ? 1 : 0.5)
        )
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
        let text = card.frontText
        if let img = thumbnail {
            HStack(spacing: 10) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                if !text.isEmpty {
                    Text(text).font(.subheadline).lineLimit(2).multilineTextAlignment(.leading)
                }
            }
        } else if !text.isEmpty {
            Text(text).font(.subheadline).lineLimit(3).multilineTextAlignment(.leading)
        } else if didLoad {
            Text("Empty card").font(.subheadline).foregroundStyle(.tertiary)
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

    private var cardBackground: some ShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground))
            : AnyShapeStyle(Color.white)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.06)
    }
}

// =============================================================================
// MARK: - Zone Helpers
//
// Changed from `private` to `internal` so CardFetchActor.generateThumbnail
// (defined in CardFetchActor.swift) can call them from the same module.
// All three are pure, stateless functions with no SwiftData dependencies.
// =============================================================================

func getFirstImageData(from zone: ZoneModel) -> Data? {
    if zone.isLeaf {
        guard zone.contentType == .image || zone.contentType == .sketch else { return nil }
        return zone.imageData
    }
    return zone.children?.lazy.compactMap { getFirstImageData(from: $0) }.first
}

func containsMedia(_ zone: ZoneModel, contentType: ZoneContentType) -> Bool {
    if zone.isLeaf { return zone.contentType == contentType && zone.imageData != nil }
    return zone.children?.contains { containsMedia($0, contentType: contentType) } ?? false
}

func downsample(data: Data, maxDimension: CGFloat) -> UIImage? {
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
            Circle().strokeBorder(isSelected ? accent : Color.secondary.opacity(0.3), lineWidth: 2)
            if isSelected {
                Circle().fill(accent)
                Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .background(.ultraThinMaterial, in: Circle())
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
