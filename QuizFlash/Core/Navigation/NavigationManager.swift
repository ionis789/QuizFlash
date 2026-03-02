//
//  NavigationManager.swift
//  QuizFlash
//
//  Created by Ion Socol on 01.02.2026.
//

import SwiftUI
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

enum AppRoute: Hashable {
    case createDeck
    case settings
    case folder(FolderModel)
}

// MARK: - Search Route Integration
// Explicit route used to pass the search context forward without polluting DeckModel.
struct DeckSearchRoute: Hashable {
    let deck: DeckModel
    let query: String
}
