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

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        let handled = GIDSignIn.sharedInstance.handle(url)
#if DEBUG
        print(
            "AUTH_SESSION_FLOW \(String(format: "%.3f", Date().timeIntervalSince1970)) "
                + "Google callback URL handled=\(handled)"
        )
#endif
        return handled
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
    @State private var onboardingStateStore = OnboardingStateStore.shared

    init() {
        AppLocalization.applyLanguageOverride(AppPreferences.shared.appLanguage)
    }

    var body: some Scene {
        WindowGroup {
            CloudSessionBootstrapper()
                .id(appPreferences.languageRefreshKey)
                .fontDesign(.rounded)
                .environment(authManager)
                .environment(themeManager)
                .environment(aiProviderStore)
                .environment(appPreferences)
                .environment(developmentPreferences)
                .environment(appMigrationStore)
                .environment(subscriptionManager)
                .environment(cloudUserProfileService)
                .environment(cloudSyncCoordinator)
                .environment(onboardingStateStore)
                .environment(\.locale, appPreferences.resolvedLocale)
                .tint(themeManager.accentColor.color)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    let handled = GIDSignIn.sharedInstance.handle(url)
#if DEBUG
                    print(
                        "AUTH_SESSION_FLOW \(String(format: "%.3f", Date().timeIntervalSince1970)) "
                            + "Google SwiftUI callback URL handled=\(handled)"
                    )
#endif
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
