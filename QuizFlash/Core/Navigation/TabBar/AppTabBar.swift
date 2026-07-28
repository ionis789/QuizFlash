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

    static var visibleTabs: [AppTabBar] {
        [.home, .library, .create, .settings]
    }

    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        case .create: return "Create"
        case .settings: return "Settings"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .home:
            return AppLocalization.string("Home", locale: locale)
        case .library:
            return AppLocalization.string("Library", locale: locale)
        case .create:
            return AppLocalization.string("Create", locale: locale)
        case .settings:
            return AppLocalization.string("Settings", locale: locale)
        }
    }

    var symbol: String {
        switch self {
        case .home: return "bolt.fill"
        case .library: return "rectangle.stack.fill"
        case .create: return "book.and.wrench"
        case .settings: return "gearshape"
        }
    }

    var index: Int {
        Self.visibleTabs.firstIndex(of: self) ?? 0
    }
}
