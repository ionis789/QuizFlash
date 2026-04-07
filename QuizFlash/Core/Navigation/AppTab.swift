//
//  AppTab.swift
//  QuizFlash
//
//  Created by Ion Socol on 22.12.2025.
//

import SwiftUI

<<<<<<< Updated upstream:QuizFlash/Core/Navigation/AppTab.swift
enum AppTab: String, CaseIterable, Identifiable {
    case library, create, settings
    
=======
enum AppTabBar: String, CaseIterable, Identifiable {
    case home = "HOME"
    case library = "LIBRARY"
    case labs = "LABS"
    case create = "CREATE"
    case settings = "SETTINGS"

>>>>>>> Stashed changes:QuizFlash/Core/Navigation/TabBar/AppTabBar.swift
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .library: return "Library"
        case .labs: return "Labs"
        case .create: return "Create"
        case .settings: return "Settings"
        }
    }
    
    var icon: String {
        switch self {
        case .library: return "rectangle.stack"
<<<<<<< Updated upstream:QuizFlash/Core/Navigation/AppTab.swift
        case .create: return "plus.circle"
=======
        case .labs: return "testtube.2"
        case .create: return "book.and.wrench"
>>>>>>> Stashed changes:QuizFlash/Core/Navigation/TabBar/AppTabBar.swift
        case .settings: return "gearshape"
        }
    }
}
