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

    @State var authManager = AuthManager()
    @State private var themeManager = ThemeManager.shared

    init() {
        //
        MathWebViewPool.shared.prewarm()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authManager)
                .tint(themeManager.accentColor.color)
                .preferredColorScheme(.dark)
                .onAppear {
                    print(URL.documentsDirectory.path())
                }
        }
            .modelContainer(for: [FolderModel.self, DeckModel.self, CardModel.self, ReviewEvent.self, UserProfile.self, DailyActivityLog.self])
    }
}

