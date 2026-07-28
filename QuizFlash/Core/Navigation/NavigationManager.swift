//
//  NavigationManager.swift
//  QuizFlash
//
//  Observable navigation coordinator that manages isolated navigation stacks per tab,
//  preventing view teardowns and memory leaks on iOS 17.
//

import SwiftUI
import SwiftData

// MARK: - Navigation Manager

/// An observable navigation coordinator that owns one `NavigationPath` per app tab.
///
/// Inject the shared instance at the root `NavigationStack` level via `.environment(NavigationManager())`.
/// Child views that need to push routes call `router.append(_:)` and `router.popToRoot()`.
///
/// Using isolated paths per tab ensures that switching tabs does not tear down
/// and re-create deep navigation stacks, preventing the iOS 17 `ModelContext` row-cache trap.
@Observable
final class NavigationManager {
    // MARK: - Navigation Paths

    /// The navigation stack for the **Home** tab.
    var homePath = NavigationPath()

    /// The navigation stack for the **Library** tab.
    var libraryPath = NavigationPath()

    /// The navigation stack for the **Create** tab.
    var createPath = NavigationPath()

    /// The existing deck currently loaded into the Create-tab root workspace.
    ///
    /// `nil` means the root workspace should render an empty create session.
    var createWorkspaceEditingDeckID: PersistentIdentifier? = nil

    /// Stable identity used to reconstruct the Create-tab root workspace only
    /// when the root editing context is intentionally replaced.
    var createWorkspaceRootIdentity = UUID()

    /// The navigation stack for the **Settings** tab.
    var settingsPath = NavigationPath()

    // MARK: - Active Tab

    /// The currently visible tab.
    ///
    /// Cross-feature navigations (e.g. a Today widget tapping into a deck) must
    /// update this before calling `append(_:)` so the route lands on the correct stack.
    var activeTab: AppTabBar = .home

    // MARK: - Navigation Actions

    /// Pops the active tab's navigation stack back to its root view.
    func popToRoot() {
        switch activeTab {
        case .home: homePath = NavigationPath()
        case .library: libraryPath = NavigationPath()
        case .create: createPath = NavigationPath()
        case .settings: settingsPath = NavigationPath()
        }
    }

    /// Appends a route to the active tab's navigation stack.
    ///
    /// - Parameter route: Any `Hashable` route value recognised by the active tab's
    ///   `.navigationDestination(for:)` modifier.
    func append<V: Hashable>(_ route: V) {
        switch activeTab {
        case .home: homePath.append(route)
        case .library: libraryPath.append(route)
        case .create: createPath.append(route)
        case .settings: settingsPath.append(route)
        }
    }

    /// Activates the Create tab and resets its stack back to the root editor.
    func showCreateRoot() {
        activeTab = .create
        createPath = NavigationPath()
    }

    /// Activates the Create tab and resets the root workspace back to an empty create session.
    func showEmptyCreateWorkspace() {
        showCreateRoot()
        createWorkspaceEditingDeckID = nil
        createWorkspaceRootIdentity = UUID()
    }

    /// Activates the Create tab and replaces the root workspace with an existing deck session.
    ///
    /// - Parameter deckID: The persisted deck identifier that should host the workspace runtime.
    func showDeckWorkspace(for deckID: PersistentIdentifier) {
        showCreateRoot()
        createWorkspaceEditingDeckID = deckID
        createWorkspaceRootIdentity = UUID()
    }

    /// Releases any stale root editing context without reconstructing the visible workspace.
    func clearCreateWorkspaceEditingContext() {
        createWorkspaceEditingDeckID = nil
    }

}

// MARK: - App Route

/// A type-safe enum of all named navigation destinations shared across tabs.
enum AppRoute {
    /// Navigates to the deck creation flow.
    case createDeck
    /// Navigates to the deck creation flow and immediately foregrounds AI generation.
    case generateDeck
    /// Navigates to the app settings screen.
    case settings
    /// Navigates into a folder's deck list.
    ///
    /// `backLabel` is encoded at push time so `FolderView` never needs to read
    /// `router.activeTab` reactively. A reactive read would cause `FolderView` to
    /// re-render mid tab-switch (when `activeTab` changes), making the back-button
    /// text update while the view is still visible in the cross-fade animation.
    case folder(FolderModel, backLabel: String)
}

extension AppRoute: Equatable {
    static func == (lhs: AppRoute, rhs: AppRoute) -> Bool {
        switch (lhs, rhs) {
        case (.createDeck, .createDeck): return true
        case (.generateDeck, .generateDeck): return true
        case (.settings, .settings): return true
        // `backLabel` is intentionally excluded — two pushes to the same folder
        // are the same route regardless of which tab initiated them.
        case (.folder(let a, _), .folder(let b, _)):
            return a.persistentModelID == b.persistentModelID
        default: return false
        }
    }
}

extension AppRoute: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case .createDeck: hasher.combine(0)
        case .generateDeck: hasher.combine(1)
        case .settings: hasher.combine(2)
        // `backLabel` excluded — consistent with `Equatable` above.
        case .folder(let f, _): hasher.combine(3)
            hasher.combine(f.persistentModelID)
        }
    }
}

// MARK: - Deck Search Route

/// A route that carries a search context into a `DeckView` without polluting `DeckModel`.
///
/// Passed via `NavigationManager.append(_:)` when the user taps a deck from `SearchResultsView`.
struct DeckSearchRoute {
    /// The deck to open.
    let deck: DeckModel
    /// The search query string used to determine which cards to highlight.
    let query: String
}

extension DeckSearchRoute: Equatable {
    static func == (lhs: DeckSearchRoute, rhs: DeckSearchRoute) -> Bool {
        lhs.deck.persistentModelID == rhs.deck.persistentModelID && lhs.query == rhs.query
    }
}

extension DeckSearchRoute: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(deck.persistentModelID)
        hasher.combine(query)
    }
}
