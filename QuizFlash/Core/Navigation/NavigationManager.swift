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
    var path = NavigationPath()

    func popToRoot() {
        path = NavigationPath()
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
