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

    static func visibleTabs(features: AppFeatures) -> [AppTabBar] {
        return [.home, .library, .create, .settings]
    }

    static var visibleTabs: [AppTabBar] {
        visibleTabs(features: .current)
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

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .home:
            return AppLocalization.string("Home", locale: locale)
        case .library:
            return AppLocalization.string("Library", locale: locale)
        case .labs:
            return AppLocalization.string("Labs", locale: locale)
        case .create:
            return AppLocalization.string("Create", locale: locale)
        case .settings:
            return AppLocalization.string("Settings", locale: locale)
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
