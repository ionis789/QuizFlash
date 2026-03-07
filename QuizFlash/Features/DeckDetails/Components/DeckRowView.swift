import SwiftUI
import SwiftData

struct DeckRowView: View {
    let deck: DeckModel

    // Per-deck new-card count, initialized from a process-scoped cache so the
    // badge renders with the correct value on the very first layout pass after
    // view recreation (e.g. tab switch path restoration).
    // Without this, @State would initialize to 0, causing a visible badge
    // disappear → reappear flash on every tab switch back to an open folder.
    @State private var newCardsCount: Int

    @Environment(\.modelContext) private var context

    // MARK: - Static Count Cache

    /// Process-scoped cache: PersistentIdentifier → last-known new-card count.
    /// Written after every successful async fetch; read at init time to provide
    /// a non-zero starting value that prevents the badge flash on re-render.
    /// Dictionary access is always on the MainActor, so no synchronization needed.
    @MainActor
    private static var cachedNewCardCounts: [PersistentIdentifier: Int] = [:]

    // MARK: - Init

    init(deck: DeckModel) {
        self.deck = deck
        // Seed @State from the cache so the badge value is correct before the
        // async task fires. On first-ever render the cache miss returns 0, which
        // is indistinguishable from "no new cards" — an acceptable initial state.
        self._newCardsCount = State(
            initialValue: DeckRowView.cachedNewCardCounts[deck.persistentModelID] ?? 0
        )
    }

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }
    
    // Relative date formatter to replace the hardcoded "12 min ago"
    private var timeAgoString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        // Fallback to createdAt if editedAt is exactly the same or we just want a general "last touched" metric
        // But DeckModel has both, editedAt is usually more relevant for an active deck.
        return formatter.localizedString(for: deck.editedAt, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // 1. Rândul superior: Titlu, Folder Badge și Chevron
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(deck.title)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    // ── Folder Indicator Badge ────────────────────────────────
                    // Safely reading a to-one relationship does not trigger the iOS 17 array retain cycle bug.
                    if let folder = deck.folder {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                            Text(folder.title)
                        }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(white: 0.6))
                    .padding(.top, 4) // Align nicely with the multiline title area
            }

            // 2. Rândul inferior: Statistici și Badge
            HStack(alignment: .center, spacing: 16) {

                // Numărul de carduri — reads the denormalized stored property,
                // NO relationship faulting.
                HStack(spacing: 6) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14))
                    Text("\(deck.cardCount) cards")
                        .font(.system(size: 14, weight: .medium))
                }
                    .foregroundColor(Color(white: 0.7))

                // Timpul scurs
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 14))
                    Text(timeAgoString)
                        .font(.system(size: 14, weight: .medium))
                }
                    .foregroundColor(Color(white: 0.7))

                Spacer()

                // Badge-ul (Apare doar dacă sunt carduri noi)
                if newCardsCount > 0 {
                    ZStack {
                        Circle()
                            .fill(
                            Color(accent).opacity(0.35)
                        )
                            .frame(width: 20, height: 20)

                        Text("\(newCardsCount)")
                            .font(.caption2.bold())
                            .foregroundColor(.primary)
                    }
                }
            }
        }
            .padding(16)
            .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                Color.libraryDeckRow
                    .shadow(.inner(color: Color.white.opacity(0.15), radius: 1, x: 0, y: 0))
            )
        }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .task(id: deck.persistentModelID) {
            // Use a THROWAWAY ModelContext to count new cards.
            // This avoids faulting ANY CardModel into the main context's
            // permanent row cache (iOS 17 has no ModelContext.reset()).
            guard deck.cardCount > 0 else { return }
            // Yield to unblock the current layout pass.
            try? await Task.sleep(for: .milliseconds(1))
            guard !Task.isCancelled else { return }
            let container = context.container
            let deckID = deck.persistentModelID
            let count = await Self.fetchNewCardCount(deckID: deckID, container: container)
            guard !Task.isCancelled else { return }
            // Persist the result so the next recreation of this view (e.g. after
            // a tab switch) can seed @State with the correct value immediately.
            DeckRowView.cachedNewCardCounts[deckID] = count
            newCardsCount = count
        }
    }

    @MainActor
    private static var sharedActor: DeckRowActor?

    @MainActor
    private static func getSharedActor(container: ModelContainer) -> DeckRowActor {
        if let actor = sharedActor { return actor }
        let actor = DeckRowActor(modelContainer: container)
        sharedActor = actor
        return actor
    }

    /// Uses a safe `@ModelActor` to scan for new cards without leaking manual `ModelContext` instances on iOS 17.
    /// Uses a singleton actor to prevent iOS 17 executor queues from leaking on every scroll cell `Task`.
    private static func fetchNewCardCount(deckID: PersistentIdentifier, container: ModelContainer) async -> Int {
        let actor = await getSharedActor(container: container)
        return await actor.countNewCards(for: deckID)
    }
}

// =============================================================================
// MARK: - Safe Background Actor (iOS 17 Memory Leak Fix)
// =============================================================================

/// A custom background actor for counting new cards without touching the main
/// `ModelContext`. Implements the same lazy-context pattern as `LibrarySearchActor`
/// to prevent the "ModelContext: Unbinding from the main queue" warning.
///
/// Root cause: `getSharedActor(container:)` is `@MainActor`, so the actor's
/// `init` body executes on the MainActor (Swift non-async actor inits are not
/// isolated to the actor's executor). Creating `ModelContext` in `init` would
/// therefore instantiate it on the MainActor, while `countNewCards` uses it on
/// the background executor → SwiftData "Unbinding" warning. The lazy accessor
/// defers context creation to the first actor-isolated call, guaranteeing
/// instantiation and use share the same executor.
final actor DeckRowActor {
    private let modelContainer: ModelContainer
    /// Backing store — nil until first actor-isolated access.
    private var _context: ModelContext?

    /// Actor-isolated accessor. Created lazily on the actor's background executor.
    private var context: ModelContext {
        if let existing = _context { return existing }
        let ctx = ModelContext(modelContainer)
        _context = ctx
        return ctx
    }

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        // Intentionally no ModelContext creation here. See actor-level comment.
    }

    func countNewCards(for deckID: PersistentIdentifier) -> Int {
        var desc = FetchDescriptor<CardModel>(predicate: #Predicate {
            $0.deck?.persistentModelID == deckID &&
                $0.interval == 0 &&
                $0.consecutiveCorrectAnswers == 0
        })

        // Optimise: count only — no need to materialise full model objects.
        desc.propertiesToFetch = [\.persistentModelID]

        let count = (try? context.fetchCount(desc)) ?? 0

        // Sever NotificationCenter observer ties accumulated during the fetch.
        // Niling the reference forces lazy recreation on the next call, which
        // is the only reliable way to free the row cache on iOS 17.
        flushRAM()

        return count
    }

    /// Drops the current context reference. The lazy accessor recreates it on
    /// the next actor-isolated call, on the actor's own background executor.
    private func flushRAM() {
        _context = nil
    }
}
