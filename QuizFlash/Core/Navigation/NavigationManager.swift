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
}
