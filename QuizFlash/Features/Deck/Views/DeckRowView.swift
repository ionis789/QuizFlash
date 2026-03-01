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
                    Text("12 min ago")
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

/// A custom background actor implementing strictly "Pilonul 1" & "Pilonul 2".
/// It manually manages the ModelContext and flushes RAM to prevent the
/// iOS 17 NotificationCenter Zombie Context memory leak.
final actor DeckRowActor {
    private let modelContainer: ModelContainer
    private var backgroundContext: ModelContext

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.backgroundContext = ModelContext(modelContainer)
    }

    func countNewCards(for deckID: PersistentIdentifier) -> Int {
        var desc = FetchDescriptor<CardModel>(predicate: #Predicate {
            $0.deck?.persistentModelID == deckID &&
                $0.interval == 0 &&
                $0.consecutiveCorrectAnswers == 0
        })

        // Optimize: We only need the count.
        desc.propertiesToFetch = [\.persistentModelID]

        let count = (try? backgroundContext.fetchCount(desc)) ?? 0

        // 🟢 PILONUL 2: FLUSH RAM
        // Distrugem contextul actual și îl recreăm pentru a tăia
        // legăturile invizibile cu NotificationCenter și row cache.
        flushRAM()

        return count
    }

    private func flushRAM() {
        self.backgroundContext = ModelContext(modelContainer)
    }
}
