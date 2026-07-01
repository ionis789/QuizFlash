//
//  SubscriptionManager.swift
//  QuizFlash
//

import FirebaseAuth
import FirebaseFirestore
import Foundation
import Observation

// MARK: - Subscription Manager

/// Reads the current subscription state from Firebase while App Store setup is unavailable.
@Observable
@MainActor
final class SubscriptionManager {

    // MARK: - Shared

    static let shared = SubscriptionManager()
    static let defaultFreeGenerationsLimit = 5
    static let freeMaxCardsPerGeneration = 30
    static let premiumMaxCardsPerGeneration = 100
    static let defaultPremiumMonthlyAIUsageLimitMicroUSD = 2_000_000

    // MARK: - State

    private(set) var isPremium = false
    private(set) var planSource: SubscriptionPlanSource = .none
    private(set) var freeGenerationsUsed: Int?
    private(set) var freeGenerationsLimit: Int?
    private(set) var cloudAIUsageQuota: CloudAIQuotaState?
    private(set) var cloudAIGenerationHistory: [CloudAIGenerationUsageRecord] = []
    private(set) var lastErrorMessage: String?
    var presentPaywall = false

    @ObservationIgnored
    private var cachedFirestore: Firestore?

    @ObservationIgnored
    private var activeUID: String?

    // MARK: - Init

    init() { }

    init(firestore: Firestore) {
        self.cachedFirestore = firestore
    }

    // MARK: - Public

    /// Refreshes premium state for the current Firebase user.
    func configure(for user: AuthUserSnapshot?) async {
        guard let user else {
            await BackendTraceStore.shared.record(
                "configure-signed-out",
                layer: "subscription"
            )
            applySignedOutState()
            return
        }

        await BackendTraceStore.shared.record(
            "configure-signed-in",
            layer: "subscription",
            details: ["uid": BackendTraceStore.safeUID(user.uid)]
        )
        await refresh(uid: user.uid)
    }

    /// Re-reads custom claims and the user profile document.
    func refresh(uid: String? = Auth.auth().currentUser?.uid) async {
        guard let uid else {
            await BackendTraceStore.shared.record(
                "refresh-no-user",
                layer: "subscription"
            )
            applySignedOutState()
            return
        }

        prepareStateForUIDIfNeeded(uid)
        await BackendTraceStore.shared.record(
            "firestore-user-read-start",
            layer: "subscription",
            details: ["path": "users/\(BackendTraceStore.safeUID(uid))"]
        )

        do {
            let userData = try await firestore
                .collection("users")
                .document(uid)
                .getDocument()
                .data()

            let profilePremium = userData?["premium"] as? Bool
            let profilePlan = userData?["plan"] as? String
            let resolvedProfilePremium = profilePremium ?? (profilePlan == "premium")
            lastErrorMessage = nil
            await BackendTraceStore.shared.record(
                "firestore-user-read-success",
                layer: "subscription",
                details: firestoreUserDetails(userData, resolvedPremium: resolvedProfilePremium)
            )

            if resolvedProfilePremium {
                isPremium = true
                planSource = .manualFirestore
            } else {
                isPremium = false
                planSource = .free
            }

            let usage = userData?["freeGenerationsUsed"] as? Int
            let limit = userData?["freeGenerationsLimit"] as? Int
            if isPremium {
                clearFreeQuota()
            } else {
                applyFreeQuota(used: usage, limit: limit)
            }
            await BackendTraceStore.shared.record(
                "local-plan-applied",
                layer: "subscription",
                details: [
                    "premium": String(isPremium),
                    "planSource": planSource.rawValue,
                    "freeUsed": String(freeGenerationsUsed ?? -1),
                    "freeLimit": String(freeGenerationsLimit ?? -1)
                ]
            )

            await refreshCloudAIUsageQuota()
            if isPremium {
                await refreshCloudAIGenerationHistory()
            } else {
                cloudAIGenerationHistory = []
            }
        } catch {
            await BackendTraceStore.shared.record(
                "firestore-user-read-error",
                layer: "subscription",
                details: [
                    "uid": BackendTraceStore.safeUID(uid),
                    "error": error.localizedDescription
                ]
            )
            lastErrorMessage = error.localizedDescription
        }
    }

    func aiGenerationLimitMessage(locale: Locale) -> String? {
        guard !isPremium,
              let freeGenerationsUsed,
              let freeGenerationsLimit,
              freeGenerationsUsed >= freeGenerationsLimit else {
            return nil
        }

        return AppLocalization.string("Upgrade to Premium to generate more cards.", locale: locale)
    }

    var maxCardsPerGeneration: Int {
        isPremium ? Self.premiumMaxCardsPerGeneration : Self.freeMaxCardsPerGeneration
    }

    var cloudAIUsageProgress: Double {
        cloudAIUsageQuotaForDisplay?.usageProgress ?? 0
    }

    var cloudAIUsageQuotaForDisplay: CloudAIQuotaState? {
        if let cloudAIUsageQuota {
            if !isPremium || (cloudAIUsageQuota.limitMicroUSD ?? 0) > 0 {
                return cloudAIUsageQuota
            }
        }

        guard isPremium else { return nil }
        return CloudAIQuotaState(
            premium: true,
            freeGenerationsUsed: nil,
            freeGenerationsLimit: nil,
            monthlyCostMicroUSD: 0,
            limitMicroUSD: Self.defaultPremiumMonthlyAIUsageLimitMicroUSD,
            consumedMicroUSD: 0,
            reservedMicroUSD: 0,
            availableMicroUSD: Self.defaultPremiumMonthlyAIUsageLimitMicroUSD,
            percent: 0
        )
    }

    func refreshCloudAIUsageQuota() async {
        guard Auth.auth().currentUser != nil else {
            await BackendTraceStore.shared.record(
                "quota-refresh-no-user",
                layer: "subscription"
            )
            cloudAIUsageQuota = nil
            return
        }

        do {
            await BackendTraceStore.shared.record(
                "quota-refresh-start",
                layer: "subscription"
            )
            applyCloudAIQuotaState(try await CloudAIProxyClient.shared.currentUsageQuota())
        } catch {
            await BackendTraceStore.shared.record(
                "quota-refresh-error",
                layer: "subscription",
                details: ["error": error.localizedDescription]
            )
            if isPremium {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    func refreshCloudAIGenerationHistory() async {
        guard Auth.auth().currentUser != nil else {
            await BackendTraceStore.shared.record(
                "generation-history-no-user",
                layer: "subscription"
            )
            cloudAIGenerationHistory = []
            return
        }

        guard isPremium else {
            await BackendTraceStore.shared.record(
                "generation-history-skipped-free",
                layer: "subscription"
            )
            cloudAIGenerationHistory = []
            return
        }

        do {
            await BackendTraceStore.shared.record(
                "generation-history-start",
                layer: "subscription"
            )
            cloudAIGenerationHistory = try await CloudAIProxyClient.shared.currentUsageGenerations()
            await BackendTraceStore.shared.record(
                "generation-history-success",
                layer: "subscription",
                details: ["count": String(cloudAIGenerationHistory.count)]
            )
            lastErrorMessage = nil
        } catch {
            await BackendTraceStore.shared.record(
                "generation-history-error",
                layer: "subscription",
                details: ["error": error.localizedDescription]
            )
            lastErrorMessage = error.localizedDescription
        }
    }

    func applyCloudAIQuotaState(_ state: CloudAIQuotaState) {
        isPremium = state.premium
        planSource = state.premium ? .manualFirestore : .free
        if state.premium {
            clearFreeQuota()
        } else {
            applyFreeQuota(
                used: state.freeGenerationsUsed,
                limit: state.freeGenerationsLimit
            )
        }
        cloudAIUsageQuota = state
        lastErrorMessage = nil
        Task {
            await BackendTraceStore.shared.record(
                "quota-state-applied",
                layer: "subscription",
                details: Self.quotaDetails(state)
            )
        }
    }

    /// Placeholder action until App Store Connect purchases are available.
    func restorePurchases() async throws {
        throw SubscriptionManagerError.storeUnavailable
    }

    // MARK: - Private

    private func applySignedOutState() {
        activeUID = nil
        isPremium = false
        planSource = .none
        clearFreeQuota()
        lastErrorMessage = nil
        cloudAIUsageQuota = nil
        cloudAIGenerationHistory = []
    }

    private func prepareStateForUIDIfNeeded(_ uid: String) {
        guard activeUID != uid else { return }
        activeUID = uid
        clearFreeQuota()
        cloudAIUsageQuota = nil
        cloudAIGenerationHistory = []
    }

    private func clearFreeQuota() {
        freeGenerationsUsed = nil
        freeGenerationsLimit = nil
    }

    private func applyFreeQuota(used: Int?, limit: Int?) {
        let resolvedLimit = max(limit ?? freeGenerationsLimit ?? Self.defaultFreeGenerationsLimit, 0)
        let resolvedUsed = max(used ?? freeGenerationsUsed ?? 0, 0)

        freeGenerationsUsed = resolvedUsed
        freeGenerationsLimit = resolvedLimit
    }

    private var firestore: Firestore {
        if let cachedFirestore { return cachedFirestore }
        let firestore = Firestore.firestore()
        cachedFirestore = firestore
        return firestore
    }

    private func firestoreUserDetails(
        _ data: [String: Any]?,
        resolvedPremium: Bool
    ) -> [String: String] {
        guard let data else {
            return [
                "exists": "false",
                "resolvedPremium": String(resolvedPremium)
            ]
        }

        let aiUsage = data["aiUsage"] as? [String: Any]
        return [
            "exists": "true",
            "keys": data.keys.sorted().joined(separator: ","),
            "premiumField": String(describing: data["premium"]),
            "planField": String(describing: data["plan"]),
            "resolvedPremium": String(resolvedPremium),
            "freeUsed": String(describing: data["freeGenerationsUsed"]),
            "freeLimit": String(describing: data["freeGenerationsLimit"]),
            "budgetMicroUSD": String(describing: data["aiMonthlyBudgetMicroUSD"]),
            "aiUsageKeys": aiUsage?.keys.sorted().joined(separator: ",") ?? "<none>",
            "aiUsageCost": String(describing: aiUsage?["costMicroUSD"]),
            "aiUsagePeriod": String(describing: aiUsage?["period"])
        ]
    }

    private static func quotaDetails(_ quota: CloudAIQuotaState) -> [String: String] {
        [
            "premium": String(quota.premium),
            "freeUsed": String(quota.freeGenerationsUsed ?? -1),
            "freeLimit": String(quota.freeGenerationsLimit ?? -1),
            "monthlyCostMicroUSD": String(quota.monthlyCostMicroUSD),
            "consumedMicroUSD": String(quota.consumedMicroUSD),
            "reservedMicroUSD": String(quota.reservedMicroUSD),
            "limitMicroUSD": String(quota.limitMicroUSD ?? -1),
            "availableMicroUSD": String(quota.availableMicroUSD ?? -1),
            "usageProgress": String(quota.usageProgress),
            "percent": String(quota.percent ?? -1),
            "usageBasis": quota.usageBasis ?? "unknown",
            "billingWindowKey": quota.billingWindowKey ?? "none",
            "billingWindowStartMs": String(quota.billingWindowStartMs ?? -1),
            "billingWindowEndMs": String(quota.billingWindowEndMs ?? -1)
        ]
    }

}

// MARK: - Subscription Plan Source

enum SubscriptionPlanSource: String, Sendable {
    case none
    case free
    case manualFirestore

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .none:
            return AppLocalization.string("Not signed in", locale: locale)
        case .free:
            return AppLocalization.string("Free", locale: locale)
        case .manualFirestore:
            return AppLocalization.string("Manual premium", locale: locale)
        }
    }
}

// MARK: - Subscription Manager Error

enum SubscriptionManagerError: LocalizedError {
    case storeUnavailable

    var errorDescription: String? {
        switch self {
        case .storeUnavailable:
            return "Purchases are not available until App Store Connect is ready."
        }
    }
}
