//
//  CloudSessionBootstrapper.swift
//  QuizFlash
//

import SwiftData
import SwiftUI

// MARK: - Cloud Session Bootstrapper

/// Keeps the authenticated Firebase profile, plan state, and deck sync session aligned.
struct CloudSessionBootstrapper: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(CloudSyncCoordinator.self) private var cloudSyncCoordinator
    @Environment(CloudUserProfileService.self) private var cloudUserProfileService
    @Environment(SubscriptionManager.self) private var subscriptionManager

    var body: some View {
        RootView()
            .task {
                authManager.startListening()
            }
            .task(id: authManager.sessionState) {
                let user = authManager.currentUser
                await cloudUserProfileService.upsertUserProfile(for: user)
                await subscriptionManager.configure(for: user)
                cloudSyncCoordinator.configure(for: user, modelContainer: modelContext.container)
            }
    }
}
