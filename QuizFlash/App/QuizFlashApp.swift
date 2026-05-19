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

    @State var authManager = AuthManager.shared
    @State private var themeManager = ThemeManager.shared
    @State private var aiProviderStore = AIProviderStore.shared
    @State private var appPreferences = AppPreferences.shared
    @State private var developmentPreferences = DevelopmentPreferences.shared
    @State private var cardAppearancePreferences = CardAppearancePreferences.shared
    @State private var appMigrationStore = AppMigrationStore.shared

    init() {
        AppLocalization.applyLanguageOverride(AppPreferences.shared.appLanguage)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(appPreferences.languageRefreshKey)
                .environment(authManager)
                .environment(themeManager)
                .environment(aiProviderStore)
                .environment(appPreferences)
                .environment(developmentPreferences)
                .environment(cardAppearancePreferences)
                .environment(appMigrationStore)
                .environment(\.locale, appPreferences.resolvedLocale)
                .tint(themeManager.accentColor.color)
                .quizFlashAppTextSize(appPreferences)
                .preferredColorScheme(.dark)
                .onAppear {
                    print(URL.documentsDirectory.path())
                }
        }
            .modelContainer(for: [
                FolderModel.self,
                DeckModel.self,
                CardModel.self,
                ReviewEvent.self,
                UserProfile.self,
                DailyActivityLog.self,
                HomeDailyStudyAggregate.self,
                HomeDailyDeckAggregate.self,
                HomeDailyCardAggregate.self,
                DeckPlayModeSettingsModel.self
            ])
    }
}

private extension View {
    @ViewBuilder
    func quizFlashAppTextSize(_ appPreferences: AppPreferences) -> some View {
        if appPreferences.usesSystemTextSize {
            self
        } else {
            dynamicTypeSize(appPreferences.appInterfaceDynamicTypeSize)
        }
    }
}
