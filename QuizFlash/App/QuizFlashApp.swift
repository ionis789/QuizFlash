//
//  QuizFlashApp.swift
//  QuizFlash
//
//  Created by Ion Socol on 21.12.2025.
//

import SwiftUI

@main
struct QuizFlashApp: App {
    
    @StateObject var authManager = AuthManager()
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
                .preferredColorScheme(.dark)
        }
    }
}
