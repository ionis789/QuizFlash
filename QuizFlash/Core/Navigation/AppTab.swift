//
//  AppTab.swift
//  QuizFlash
//

import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case library = "Library"
    case create = "Create"
    case settings = "Settings"
    
    var id: String { rawValue }
    
    var symbol: String {
        switch self {
        case .library: return "rectangle.stack"
        case .create: return "plus.circle"
        case .settings: return "gearshape"
        }
    }
    
    var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}
