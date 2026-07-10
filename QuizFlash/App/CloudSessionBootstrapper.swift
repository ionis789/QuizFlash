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
                AuthFlowDebugTrace.record(
                    "listener-task.begin",
                    layer: "bootstrap",
                    details: ["state": authManager.sessionState.debugName]
                )
                authManager.startListening()
            }
            .task(id: authManager.sessionState) {
                let user = authManager.currentUser
                AuthFlowDebugTrace.record(
                    "session-task.begin",
                    layer: "bootstrap",
                    details: [
                        "state": authManager.sessionState.debugName,
                        "user": BackendTraceStore.safeUID(user?.uid),
                        "cancelled": String(Task.isCancelled)
                    ]
                )
                await BackendTraceStore.shared.record(
                    "session-state",
                    layer: "bootstrap",
                    details: [
                        "state": sessionStateName(authManager.sessionState),
                        "uid": BackendTraceStore.safeUID(user?.uid)
                    ]
                )
                await BackendTraceStore.shared.record(
                    "profile-upsert-start",
                    layer: "bootstrap",
                    details: ["uid": BackendTraceStore.safeUID(user?.uid)]
                )
                await cloudUserProfileService.upsertUserProfile(for: user)
                AuthFlowDebugTrace.record(
                    "profile-upsert.finished",
                    layer: "bootstrap",
                    details: [
                        "state": authManager.sessionState.debugName,
                        "cancelled": String(Task.isCancelled),
                        "error": cloudUserProfileService.lastErrorMessage == nil ? "none" : "present"
                    ]
                )
                await BackendTraceStore.shared.record(
                    "profile-upsert-finished",
                    layer: "bootstrap",
                    details: [
                        "uid": BackendTraceStore.safeUID(cloudUserProfileService.lastUpsertedUID),
                        "error": cloudUserProfileService.lastErrorMessage ?? "<none>"
                    ]
                )
                await BackendTraceStore.shared.record(
                    "subscription-configure-start",
                    layer: "bootstrap",
                    details: ["uid": BackendTraceStore.safeUID(user?.uid)]
                )
                await subscriptionManager.configure(for: user)
                AuthFlowDebugTrace.record(
                    "subscription-configure.finished",
                    layer: "bootstrap",
                    details: [
                        "state": authManager.sessionState.debugName,
                        "cancelled": String(Task.isCancelled),
                        "error": subscriptionManager.lastErrorMessage == nil ? "none" : "present"
                    ]
                )
                await BackendTraceStore.shared.record(
                    "subscription-configure-finished",
                    layer: "bootstrap",
                    details: [
                        "premium": String(subscriptionManager.isPremium),
                        "freeUsed": String(subscriptionManager.freeGenerationsUsed ?? -1),
                        "freeLimit": String(subscriptionManager.freeGenerationsLimit ?? -1),
                        "usageProgress": String(format: "%.4f", subscriptionManager.cloudAIUsageProgress),
                        "error": subscriptionManager.lastErrorMessage ?? "<none>"
                    ]
                )
                cloudSyncCoordinator.configure(for: user, modelContainer: modelContext.container)
                AuthFlowDebugTrace.record(
                    "cloud-sync.configure-called",
                    layer: "bootstrap",
                    details: [
                        "state": authManager.sessionState.debugName,
                        "cancelled": String(Task.isCancelled)
                    ]
                )
                await BackendTraceStore.shared.record(
                    "cloud-sync-configure-called",
                    layer: "bootstrap",
                    details: ["uid": BackendTraceStore.safeUID(user?.uid)]
                )
            }
    }

    private func sessionStateName(_ state: AuthSessionState) -> String {
        switch state {
        case .checking:
            return "checking"
        case .signedOut:
            return "signedOut"
        case .signedIn:
            return "signedIn"
        case .emailVerificationRequired:
            return "emailVerificationRequired"
        case .emailVerificationSucceeded:
            return "emailVerificationSucceeded"
        }
    }
}
