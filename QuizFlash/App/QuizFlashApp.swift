//
//  QuizFlashApp.swift
//  QuizFlash
//
//  Created by Ion Socol on 21.12.2025.
//

import SwiftUI
import SwiftData

@main
struct QuizFlashApp: App {
    
    @StateObject var authManager = AuthManager()
    @State private var themeManager = ThemeManager.shared
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
                .tint(themeManager.accentColor.color)
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [DeckModel.self, CardModel.self])
    }
}
