//
//  AppTab.swift
//  QuizFlash
//
//  Created by Ion Socol on 22.12.2025.
//

import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case library, create, settings
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .library: return "Library"
        case .create: return "Create"
        case .settings: return "Settings"
        }
    }
    
    var icon: String {
        switch self {
        case .library: return "rectangle.stack.fill"
        case .create: return "plus.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }
}
