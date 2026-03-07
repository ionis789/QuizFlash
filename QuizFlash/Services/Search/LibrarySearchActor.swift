//
//  LibrarySearchActor.swift
//  QuizFlash
//
//  Background actor that builds search payloads for LibraryViewModel.
//
//  Extracted from `Features/Library/ViewModels/LibraryViewModel.swift` and placed
//  in `Services/Search/` — the correct architectural home for actors that perform
//  background data operations against the SwiftData store.
//
//  ## iOS 17 Zombie Context Prevention
//  This actor strictly avoids the `@ModelActor` macro because of an iOS 17 bug:
//  `@ModelActor`-generated contexts register `NotificationCenter` observers that
//  are never unregistered when the actor is deallocated, creating zombie contexts
//  that retain all model objects indefinitely in the row cache.
//
//  ## Context Lifecycle — Why Lazy
//  Swift actor `init` is NOT isolated to the actor's executor when called
//  synchronously from another isolation domain (e.g. `MainActor`). If the context
//  were created inside `init`, it would be instantiated on the `MainActor` and then
//  used on the background executor → "Unbinding from the main queue" warning.
//  The lazy accessor creates the context on the first call that occurs inside an
//  actor-isolated method, guaranteeing that instantiation and all subsequent accesses
//  share the same background executor.
//

import SwiftData
import Foundation

// MARK: - Library Search Actor

/// A background actor that fetches card text for a given set of deck identifiers
/// and assembles `DeckSearchPayload` values for the `SearchEngine` to consume.
///
/// The actor manually manages its `ModelContext` lifecycle via `flushRAM()` to
/// immediately break all `NotificationCenter` retain cycles after each use,
/// preventing the iOS 17 zombie-context memory accumulation.
final actor LibrarySearchActor {

    // MARK: - Properties

    private let modelContainer: ModelContainer

    /// Backing store — `nil` until the first actor-isolated access.
    private var _context: ModelContext?

    /// Actor-isolated accessor. Creates the context on the first call, which
    /// always occurs on the actor's background executor, never on the `MainActor`.
    private var context: ModelContext {
        if let existing = _context { return existing }
        let ctx = ModelContext(modelContainer)
        // Disabling autosave prevents `NotificationCenter` registration,
        // which is the root cause of the iOS 17 zombie context retain.
        ctx.autosaveEnabled = false
        _context = ctx
        return ctx
    }

    // MARK: - Initializer

    /// Creates a `LibrarySearchActor` bound to the given container.
    ///
    /// The `ModelContext` is NOT created here. See the file-level comment
    /// for the full rationale on why lazy initialisation is required.
    ///
    /// - Parameter modelContainer: The shared SwiftData container.
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Public Interface

    /// Fetches card text for each deck ID and returns an array of `DeckSearchPayload` values.
    ///
    /// Each deck is processed inside an `autoreleasepool` to bound peak memory usage.
    /// After all decks are processed, `flushRAM()` is called to destroy the context,
    /// cutting all `NotificationCenter` retains and freeing the row cache immediately.
    ///
    /// - Parameter deckInfos: Lightweight deck metadata snapshots (no `CardModel` references).
    /// - Returns: An array of `DeckSearchPayload` values ready for the `SearchEngine`.
    func buildPayloads(
        for deckInfos: [(id: PersistentIdentifier, title: String, icon: String, colorHex: String)]
    ) -> [DeckSearchPayload] {
        var results: [DeckSearchPayload] = []

        for info in deckInfos {
            autoreleasepool {
                let id = info.id
                let descriptor = FetchDescriptor<CardModel>(
                    predicate: #Predicate { $0.deck?.persistentModelID == id }
                )
                guard let cards = try? self.context.fetch(descriptor) else { return }

                let searchCards = cards.map {
                    CardSearchPayload(id: $0.id, frontText: $0.frontText, backText: $0.backText)
                }
                results.append(DeckSearchPayload(
                    id: info.id,
                    title: info.title,
                    icon: info.icon,
                    colorHex: info.colorHex,
                    cards: searchCards
                ))
            }
        }

        flushRAM()
        return results
    }

    /// Tears down the actor by releasing the `ModelContext`.
    ///
    /// Call this when the owning `LibraryViewModel` is being deallocated or
    /// when the folder view that owns this actor is popped from the stack.
    func tearDown() {
        flushRAM()
    }

    // MARK: - Private Helpers

    /// Destroys the current `ModelContext` by niling the backing reference.
    ///
    /// On the next access, `context` recreates it lazily on the actor's executor.
    /// This immediately severs all `NotificationCenter` observer registrations,
    /// freeing retained model objects from the iOS 17 row cache.
    private func flushRAM() {
        _context = nil
    }
}
