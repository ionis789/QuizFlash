//
//  SubscriptionManager.swift
//  QuizFlash
//

import FirebaseAuth
import FirebaseFirestore
import Foundation
import Observation
import RevenueCat

// MARK: - Subscription Manager

/// Coordinates the RevenueCat storefront while keeping the backend authoritative for access.
@Observable
@MainActor
final class SubscriptionManager {

    // MARK: - Shared

    static let shared = SubscriptionManager()
    static let defaultFreeGenerationsLimit = 5
    static let freeMaxCardsPerGeneration = 30
    static let premiumMaxCardsPerGeneration = 100
    static let defaultPremiumMonthlyAIUsageLimitMicroUSD = 1_500_000

    // MARK: - State

    private(set) var isPremium = false
    private(set) var planSource: SubscriptionPlanSource = .none
    private(set) var freeGenerationsUsed: Int?
    private(set) var freeGenerationsLimit: Int?
    private(set) var cloudAIUsageQuota: CloudAIQuotaState?
    private(set) var cloudAIGenerationHistory: [CloudAIGenerationUsageRecord] = []
    private(set) var lastErrorMessage: String?
    private(set) var monthlyPackage: Package?
    private(set) var isLoadingOfferings = false
    private(set) var isPurchaseInProgress = false
    var presentPaywall = false

    @ObservationIgnored
    private var cachedFirestore: Firestore?

    @ObservationIgnored
    private var activeUID: String?

    @ObservationIgnored
    private var revenueCatUID: String?

    // MARK: - Init

    init() { }

    init(firestore: Firestore) {
        self.cachedFirestore = firestore
    }

    // MARK: - Public

    /// Refreshes premium state for the current Firebase user.
    func configure(for user: AuthUserSnapshot?) async {
        guard let user else {
            await backendTrace(
                "configure-signed-out",
                layer: "subscription"
            )
            await signOutRevenueCatIfNeeded()
            applySignedOutState()
            return
        }

        await backendTrace(
            "configure-signed-in",
            layer: "subscription",
            details: ["uid": backendTraceSafeID(user.uid)]
        )
        prepareStateForUIDIfNeeded(user.uid)
        await configureRevenueCat(for: user.uid)
        await refresh(uid: user.uid)
    }

    /// Re-reads custom claims and the user profile document.
    func refresh(uid: String? = Auth.auth().currentUser?.uid) async {
        guard let uid else {
            await backendTrace(
                "refresh-no-user",
                layer: "subscription"
            )
            applySignedOutState()
            return
        }

        prepareStateForUIDIfNeeded(uid)
        await backendTrace(
            "firestore-user-read-start",
            layer: "subscription",
            details: ["path": "users/\(backendTraceSafeID(uid))"]
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
            await backendTrace(
                "firestore-user-read-success",
                layer: "subscription",
                details: firestoreUserDetails(userData, resolvedPremium: resolvedProfilePremium)
            )

            if resolvedProfilePremium {
                isPremium = true
                planSource = .revenueCat
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
            await backendTrace(
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
            await backendTrace(
                "firestore-user-read-error",
                layer: "subscription",
                details: [
                    "uid": backendTraceSafeID(uid),
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
            await backendTrace(
                "quota-refresh-no-user",
                layer: "subscription"
            )
            cloudAIUsageQuota = nil
            return
        }

        do {
            await backendTrace(
                "quota-refresh-start",
                layer: "subscription"
            )
            applyCloudAIQuotaState(try await CloudAIProxyClient.shared.currentUsageQuota())
        } catch {
            await backendTrace(
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
            await backendTrace(
                "generation-history-no-user",
                layer: "subscription"
            )
            cloudAIGenerationHistory = []
            return
        }

        guard isPremium else {
            await backendTrace(
                "generation-history-skipped-free",
                layer: "subscription"
            )
            cloudAIGenerationHistory = []
            return
        }

        do {
            await backendTrace(
                "generation-history-start",
                layer: "subscription"
            )
            cloudAIGenerationHistory = try await CloudAIProxyClient.shared.currentUsageGenerations()
            await backendTrace(
                "generation-history-success",
                layer: "subscription",
                details: ["count": String(cloudAIGenerationHistory.count)]
            )
            lastErrorMessage = nil
        } catch {
            await backendTrace(
                "generation-history-error",
                layer: "subscription",
                details: ["error": error.localizedDescription]
            )
            lastErrorMessage = error.localizedDescription
        }
    }

    func applyCloudAIQuotaState(_ state: CloudAIQuotaState) {
        isPremium = state.premium
        planSource = state.premium ? .revenueCat : .free
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
            await backendTrace(
                "quota-state-applied",
                layer: "subscription",
                details: Self.quotaDetails(state)
            )
        }
    }

    func loadOfferings() async throws {
        guard revenueCatIsAvailable else {
            throw SubscriptionManagerError.storeUnavailable
        }

        isLoadingOfferings = true
        defer { isLoadingOfferings = false }

        do {
            let offering = try await Purchases.shared.offerings().current
            monthlyPackage = offering?.monthly
            guard monthlyPackage != nil else {
                throw SubscriptionManagerError.offeringsUnavailable
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func purchaseMonthly() async throws -> Bool {
        guard let uid = activeUID, revenueCatIsAvailable else {
            throw SubscriptionManagerError.storeUnavailable
        }

        if monthlyPackage == nil {
            try await loadOfferings()
        }
        guard let monthlyPackage else {
            throw SubscriptionManagerError.productUnavailable
        }

        isPurchaseInProgress = true
        defer { isPurchaseInProgress = false }

        do {
            let result = try await Purchases.shared.purchase(package: monthlyPackage)
            guard !result.userCancelled else { return false }
            try await reconcileBackend(expectedUID: uid)
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    func restorePurchases() async throws {
        guard let uid = activeUID, revenueCatIsAvailable else {
            throw SubscriptionManagerError.storeUnavailable
        }

        isPurchaseInProgress = true
        defer { isPurchaseInProgress = false }

        do {
            _ = try await Purchases.shared.restorePurchases()
            try await reconcileBackend(expectedUID: uid)
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
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
        monthlyPackage = nil
    }

    private func prepareStateForUIDIfNeeded(_ uid: String) {
        guard activeUID != uid else { return }
        activeUID = uid
        clearFreeQuota()
        cloudAIUsageQuota = nil
        cloudAIGenerationHistory = []
        monthlyPackage = nil
    }

    private var revenueCatIsAvailable: Bool {
        Purchases.isConfigured && revenueCatUID == activeUID
    }

    private func configureRevenueCat(for uid: String) async {
        guard let apiKey = revenueCatPublicSDKKey else { return }

        do {
            if !Purchases.isConfigured {
                Purchases.configure(withAPIKey: apiKey, appUserID: uid)
            } else if revenueCatUID != uid {
                _ = try await Purchases.shared.logIn(uid)
            }
            guard activeUID == uid else { return }
            revenueCatUID = uid
            try await loadOfferings()
        } catch {
            guard activeUID == uid else { return }
            lastErrorMessage = error.localizedDescription
        }
    }

    private func signOutRevenueCatIfNeeded() async {
        guard Purchases.isConfigured, revenueCatUID != nil else { return }
        _ = try? await Purchases.shared.logOut()
        revenueCatUID = nil
    }

    private func reconcileBackend(expectedUID uid: String) async throws {
        let quota = try await CloudAIProxyClient.shared.syncBilling()
        guard activeUID == uid, Auth.auth().currentUser?.uid == uid else { return }
        applyCloudAIQuotaState(quota)
        await refresh(uid: uid)
    }

    private var revenueCatPublicSDKKey: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "RevenueCatPublicSDKKey") as? String else {
            return nil
        }
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
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
    case revenueCat

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .none:
            return AppLocalization.string("Not signed in", locale: locale)
        case .free:
            return AppLocalization.string("Free", locale: locale)
        case .revenueCat:
            return AppLocalization.string("Premium", locale: locale)
        }
    }
}

// MARK: - Subscription Manager Error

enum SubscriptionManagerError: LocalizedError {
    case storeUnavailable
    case offeringsUnavailable
    case productUnavailable

    var errorDescription: String? {
        switch self {
        case .storeUnavailable:
            return "Purchases are not configured yet."
        case .offeringsUnavailable:
            return "No subscription offering is currently available."
        case .productUnavailable:
            return "This subscription product is currently unavailable."
        }
    }
}
