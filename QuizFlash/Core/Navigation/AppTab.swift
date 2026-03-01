//
//  AppTab.swift
//  QuizFlash
//

import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case library = "Library"
    case create = "Create"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .library: return "rectangle.stack"
        case .create: return "book.and.wrench"
        }
    }

    var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}
