//
//  QuizFlashApp.swift
//  QuizFlash
//
//  Created by Ion Socol on 21.12.2025.
//

import FirebaseCore
import GoogleSignIn
import SwiftData
import SwiftUI
import UIKit

// MARK: - App Delegate

final class QuizFlashAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        return true
    }
}

@main
struct QuizFlashApp: App {

    @UIApplicationDelegateAdaptor(QuizFlashAppDelegate.self) private var appDelegate

    @State private var authManager = AuthManager.shared
    @State private var themeManager = ThemeManager.shared
    @State private var aiProviderStore = AIProviderStore.shared
    @State private var appPreferences = AppPreferences.shared
    @State private var developmentPreferences = DevelopmentPreferences.shared
    @State private var appMigrationStore = AppMigrationStore.shared
    @State private var subscriptionManager = SubscriptionManager.shared
    @State private var cloudUserProfileService = CloudUserProfileService.shared
    @State private var cloudSyncCoordinator = CloudSyncCoordinator.shared

    init() {
        AppLocalization.applyLanguageOverride(AppPreferences.shared.appLanguage)
    }

    var body: some Scene {
        WindowGroup {
            CloudSessionBootstrapper()
                .id(appPreferences.languageRefreshKey)
                .fontDesign(.rounded)
#if DEBUG
                .windowTouchProbe()
#endif
                .environment(authManager)
                .environment(themeManager)
                .environment(aiProviderStore)
                .environment(appPreferences)
                .environment(developmentPreferences)
                .environment(appMigrationStore)
                .environment(subscriptionManager)
                .environment(cloudUserProfileService)
                .environment(cloudSyncCoordinator)
                .environment(\.locale, appPreferences.resolvedLocale)
                .tint(themeManager.accentColor.color)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
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
