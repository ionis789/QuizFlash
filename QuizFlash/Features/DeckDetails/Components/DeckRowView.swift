import SwiftUI
import SwiftData

// MARK: - DeckRowView

/// A list-row card that displays the deck's title, folder badge, card count, last-edited
/// time, and a "new cards" badge.
///
/// Performs a lightweight background count of new (never-reviewed) cards via `DeckRowActor`
/// to avoid touching the main `ModelContext`'s row cache (iOS 17 memory-leak fix).
/// The result is seeded from a process-scoped static cache so the badge is correct on
/// the very first layout pass after view recreation (e.g. after a tab-switch).
struct DeckRowView: View {

    // MARK: - Inputs

    let deck: DeckModel

    // MARK: - Private State

    /// Per-deck new-card badge count.
    ///
    /// Initialised from the static cache so the badge renders with the correct value
    /// immediately — preventing the disappear → reappear flash on tab switches.
    @State private var newCardsCount: Int

    @Environment(\.modelContext) private var context

    // MARK: - Static Count Cache

    /// Process-scoped cache: `PersistentIdentifier` → last-known new-card count.
    ///
    /// Written after every successful async fetch; read at `init` time to provide
    /// a non-zero starting value that prevents the badge flash on re-render.
    /// Dictionary access is always on the `MainActor`, so no synchronisation is needed.
    @MainActor
    private static var cachedNewCardCounts: [PersistentIdentifier: Int] = [:]

    // MARK: - Initialisation

    init(deck: DeckModel) {
        self.deck = deck
        // Seed @State from the cache so the badge value is correct before the
        // async task fires. On first-ever render the cache miss returns 0, which
        // is indistinguishable from "no new cards" — an acceptable initial state.
        self._newCardsCount = State(
            initialValue: DeckRowView.cachedNewCardCounts[deck.persistentModelID] ?? 0
        )
    }

    // MARK: - Computed Properties

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    /// Relative time string for the deck's last-edited date (e.g. "12 min ago").
    private var timeAgoString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: deck.editedAt, relativeTo: Date())
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // MARK: Top Row: Title, Folder Badge, Chevron
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(deck.title)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    // Folder indicator badge — reading a to-one relationship does NOT
                    // trigger the iOS 17 array retain-cycle bug.
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
                    .padding(.top, 4)
            }

            // MARK: Bottom Row: Stats and New-Card Badge
            HStack(alignment: .center, spacing: 16) {

                // Card count — reads the denormalised stored property; no relationship faulting.
                HStack(spacing: 6) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14))
                    Text("\(deck.cardCount) cards")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(Color(white: 0.7))

                // Relative last-edited time
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 14))
                    Text(timeAgoString)
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(Color(white: 0.7))

                Spacer()

                // New-card badge — shown only when there are unseen cards
                if newCardsCount > 0 {
                    ZStack {
                        Circle()
                            .fill(Color(accent).opacity(0.35))
                            .frame(width: 20, height: 20)
                        Text("\(newCardsCount)")
                            .font(.caption2.bold())
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .padding(16)
        .widgetStyle(cornerRadius: 30)
        .task(id: deck.persistentModelID) {
            // Use a throwaway ModelContext on a background actor to count new cards.
            // This avoids faulting any CardModel into the main context's permanent
            // row cache (iOS 17 has no ModelContext.reset()).
            guard deck.cardCount > 0 else { return }
            // Yield to unblock the current layout pass before doing any I/O.
            try? await Task.sleep(for: .milliseconds(1))
            guard !Task.isCancelled else { return }
            let container = context.container
            let deckID    = deck.persistentModelID
            let count = await Self.fetchNewCardCount(deckID: deckID, container: container)
            guard !Task.isCancelled else { return }
            // Persist the result so the next recreation of this view can seed @State
            // with the correct value immediately (prevents badge flash on tab switch).
            DeckRowView.cachedNewCardCounts[deckID] = count
            newCardsCount = count
        }
    }

    // MARK: - Private Helpers

    @MainActor
    private static var sharedActor: DeckRowActor?

    /// Returns the existing shared actor, or creates a new one if none exists.
    @MainActor
    private static func getSharedActor(container: ModelContainer) -> DeckRowActor {
        if let actor = sharedActor { return actor }
        let actor = DeckRowActor(modelContainer: container)
        sharedActor = actor
        return actor
    }

    /// Counts new cards for a given deck using a singleton background actor.
    ///
    /// Uses a singleton actor to prevent iOS 17 executor queues from leaking on
    /// every scroll-cell `Task`.
    private static func fetchNewCardCount(deckID: PersistentIdentifier, container: ModelContainer) async -> Int {
        let actor = getSharedActor(container: container)
        return await actor.countNewCards(for: deckID)
    }
}

// MARK: - DeckRowActor

/// A custom background actor for counting new cards without touching the main
/// `ModelContext`.
///
/// Uses the same lazy-context pattern as `LibrarySearchActor` to prevent the
/// "ModelContext: Unbinding from the main queue" warning on iOS 17.
///
/// **Root cause of the lazy pattern:**
/// `getSharedActor(container:)` is `@MainActor`, so the actor's `init` body
/// executes on the `MainActor` (Swift non-async actor inits are not isolated to
/// the actor's executor). Creating `ModelContext` in `init` would instantiate it
/// on the `MainActor` while `countNewCards` uses it on the background executor →
/// SwiftData "Unbinding" warning. The lazy accessor defers context creation to
/// the first actor-isolated call, guaranteeing instantiation and use share the
/// same executor.
final actor DeckRowActor {

    // MARK: - Private Properties

    private let modelContainer: ModelContainer
    /// Backing store — `nil` until first actor-isolated access.
    private var _context: ModelContext?

    /// Actor-isolated accessor. Created lazily on the actor's background executor.
    private var context: ModelContext {
        if let existing = _context { return existing }
        let ctx = ModelContext(modelContainer)
        _context = ctx
        return ctx
    }

    // MARK: - Initialisation

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        // Intentionally no ModelContext creation here. See actor-level comment.
    }

    // MARK: - Queries

    /// Returns the number of new (never-reviewed) cards for the given deck.
    ///
    /// Uses a property-restricted `FetchDescriptor` so SwiftData materialises only
    /// the persistent identifier — no full `CardModel` objects are loaded into RAM.
    func countNewCards(for deckID: PersistentIdentifier) -> Int {
        var desc = FetchDescriptor<CardModel>(predicate: #Predicate {
            $0.deck?.persistentModelID == deckID &&
            $0.interval == 0 &&
            $0.consecutiveCorrectAnswers == 0
        })
        // Count only — no need to materialise full model objects.
        desc.propertiesToFetch = [\.persistentModelID]

        let count = (try? context.fetchCount(desc)) ?? 0

        // Sever NotificationCenter observer ties accumulated during the fetch.
        // Niling the reference forces lazy recreation on the next call — the only
        // reliable way to free the row cache on iOS 17.
        flushContext()
        return count
    }

    // MARK: - Private Helpers

    /// Drops the current context reference.
    ///
    /// The lazy accessor recreates it on the next actor-isolated call,
    /// on the actor's own background executor.
    private func flushContext() {
        _context = nil
    }
}
