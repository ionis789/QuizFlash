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

        AuthFlowDebugTrace.record(
            "app.did-finish-launching",
            layer: "app-lifecycle",
            details: ["firebaseConfigured": String(FirebaseApp.app() != nil)]
        )

#if QUIZFLASH_DEVELOPMENT
        Task { @MainActor in
            AIGenerationLabLaunchRunner.shared.startIfRequested()
        }
#endif

        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        let handled = GIDSignIn.sharedInstance.handle(url)
        AuthFlowDebugTrace.record(
            "callback-url.app-delegate",
            layer: "google-routing",
            details: [
                "scheme": url.scheme ?? "none",
                "host": url.host ?? "none",
                "handled": String(handled)
            ]
        )
        return handled
    }
}

@main
struct QuizFlashApp: App {

    @UIApplicationDelegateAdaptor(QuizFlashAppDelegate.self) private var appDelegate

    /// The single persistent container used by every app surface and background service.
    /// Creating it explicitly prevents SwiftUI from silently substituting an empty
    /// in-memory store when a persistent migration fails.
    private let modelContainer: ModelContainer = {
        let schema = Schema([
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
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Unable to open the persistent QuizFlash store: \(error)")
        }
    }()

    @State private var authManager = AuthManager.shared
    @State private var themeManager = ThemeManager.shared
    @State private var aiProviderStore = AIProviderStore.shared
    @State private var appPreferences = AppPreferences.shared
#if QUIZFLASH_DEVELOPMENT
    @State private var developmentPreferences = DevelopmentPreferences.shared
#endif
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
                .developmentDiagnostics()
                .id(appPreferences.languageRefreshKey)
                .fontDesign(.rounded)
                .environment(authManager)
                .environment(themeManager)
                .environment(aiProviderStore)
                .environment(appPreferences)
#if QUIZFLASH_DEVELOPMENT
                .environment(developmentPreferences)
#endif
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
                    AuthFlowDebugTrace.record(
                        "callback-url.swiftui",
                        layer: "google-routing",
                        details: [
                            "scheme": url.scheme ?? "none",
                            "host": url.host ?? "none",
                            "handled": String(handled)
                        ]
                    )
                }
        }
        .modelContainer(modelContainer)
    }

}
