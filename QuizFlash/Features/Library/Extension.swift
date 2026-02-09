//
//  Extension.swift
//  QuizFlash
//
//  Created by Ion Socol on 08.02.2026.
//

import SwiftUI


// MARK: - Color Extensions
extension Color {
    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components else { return nil }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}



enum SortOrder: String, CaseIterable {
    case newest = "Newest"
    case oldest = "Oldest"
    case lastEdited = "Edited"
    case alphabetical = "A-Z"

    var icon: String {
        switch self {
        case .newest: return "arrow.down"
        case .oldest: return "arrow.up"
        case .lastEdited: return "pencil"
        case .alphabetical: return "textformat.abc"
        }
    }
}

enum ViewMode: String, CaseIterable {
    case list = "List", gallery = "Gallery"
    var systemImage: String { self == .list ? "list.bullet" : "square.grid.2x2" }
}

// MARK: - Scale Button Style
// Acesta imită comportamentul nativ de apăsare, dar ne permite să-l folosim într-un Button custom
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}
