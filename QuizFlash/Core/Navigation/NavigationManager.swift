//
//  NavigationManager.swift
//  QuizFlash
//
//  Created by Ion Socol on 01.02.2026.
//

import SwiftUI
import SwiftData
import Combine

@Observable
final class NavigationManager {
    // Isolated Navigation Paths per Tab
    var homePath = NavigationPath()
    var libraryPath = NavigationPath()
    var createPath = NavigationPath()
    
    // Tracks the current tab so cross-app navigations push to the right stack.
    var activeTab: AppTabBar = .home

    func popToRoot() {
        switch activeTab {
        case .home: homePath = NavigationPath()
        case .library: libraryPath = NavigationPath()
        case .create: createPath = NavigationPath()
        }
    }
    
    func append<V: Hashable>(_ route: V) {
        switch activeTab {
        case .home: homePath.append(route)
        case .library: libraryPath.append(route)
        case .create: createPath.append(route)
        }
    }
}

enum AppRoute {
    case createDeck
    case settings
    // backLabel is encoded at push time so FolderView never needs to read
    // router.activeTab reactively. A reactive read would cause FolderView to
    // re-render mid-tab-switch (when activeTab changes), making the back button
    // text update while the view is still visible in the cross-fade animation.
    case folder(FolderModel, backLabel: String)
}

extension AppRoute: Equatable {
    static func == (lhs: AppRoute, rhs: AppRoute) -> Bool {
        switch (lhs, rhs) {
        case (.createDeck, .createDeck): return true
        case (.settings, .settings): return true
        // backLabel is intentionally excluded from equality — two pushes to the
        // same folder are the same route regardless of which tab initiated them.
        case (.folder(let a, _), .folder(let b, _)): return a.persistentModelID == b.persistentModelID
        default: return false
        }
    }
}

extension AppRoute: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case .createDeck: hasher.combine(0)
        case .settings:   hasher.combine(1)
        // backLabel excluded from hash — consistent with Equatable above.
        case .folder(let f, _): hasher.combine(2); hasher.combine(f.persistentModelID)
        }
    }
}

// MARK: - Search Route Integration
// Explicit route used to pass the search context forward without polluting DeckModel.
struct DeckSearchRoute {
    let deck: DeckModel
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
