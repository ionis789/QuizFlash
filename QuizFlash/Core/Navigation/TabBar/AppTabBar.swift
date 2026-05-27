//
//  AppTab.swift
//  QuizFlash
//

import SwiftUI

enum AppTabBar: String, CaseIterable, Identifiable {
    case home = "HOME"
    case library = "LIBRARY"
    case create = "CREATE"
    case settings = "SETTINGS"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        case .create: return "Create"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .library: return "rectangle.stack"
        case .create: return "book.and.wrench"
        case .settings: return "gearshape"
        }
    }

    var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}
