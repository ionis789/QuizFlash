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
    
    // Tracks the current tab so cross-app navigations push to the right stack
    var activeTab: AppTab = .home

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
    case folder(FolderModel)
}

extension AppRoute: Equatable {
    static func == (lhs: AppRoute, rhs: AppRoute) -> Bool {
        switch (lhs, rhs) {
        case (.createDeck, .createDeck): return true
        case (.settings, .settings): return true
        case (.folder(let a), .folder(let b)): return a.persistentModelID == b.persistentModelID
        default: return false
        }
    }
}

extension AppRoute: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case .createDeck: hasher.combine(0)
        case .settings:   hasher.combine(1)
        case .folder(let f): hasher.combine(2); hasher.combine(f.persistentModelID)
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
