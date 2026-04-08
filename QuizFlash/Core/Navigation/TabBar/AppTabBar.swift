//
//  AppTab.swift
//  QuizFlash
//

import SwiftUI

enum AppTabBar: String, CaseIterable, Identifiable {
    case home = "HOME"
    case library = "LIBRARY"
    case labs = "LABS"
    case create = "CREATE"
    case settings = "SETTINGS"

    var id: String { rawValue }

    static var visibleTabs: [AppTabBar] {
        if AppBuildConfiguration.current.showsDevelopmentTools {
            return [.home, .library, .labs, .create, .settings]
        }

        return [.home, .library, .create, .settings]
    }

    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        case .labs: return "Labs"
        case .create: return "Create"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .library: return "rectangle.stack"
        case .labs: return "testtube.2"
        case .create: return "book.and.wrench"
        case .settings: return "gearshape"
        }
    }

    var index: Int {
        Self.visibleTabs.firstIndex(of: self) ?? 0
    }
}
