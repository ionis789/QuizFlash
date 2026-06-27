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
            applySignedOutState()
            return
        }

        await refresh(uid: user.uid)
    }

    /// Re-reads custom claims and the user profile document.
    func refresh(uid: String? = Auth.auth().currentUser?.uid) async {
        guard let uid else {
            applySignedOutState()
            return
        }

        prepareStateForUIDIfNeeded(uid)

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

            await refreshCloudAIUsageQuota()
            if isPremium {
                await refreshCloudAIGenerationHistory()
            } else {
                cloudAIGenerationHistory = []
            }
        } catch {
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
            cloudAIUsageQuota = nil
            return
        }

        do {
            applyCloudAIQuotaState(try await CloudAIProxyClient.shared.currentUsageQuota())
        } catch {
            if isPremium {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    func refreshCloudAIGenerationHistory() async {
        guard Auth.auth().currentUser != nil else {
            cloudAIGenerationHistory = []
            return
        }

        guard isPremium else {
            cloudAIGenerationHistory = []
            return
        }

        do {
            cloudAIGenerationHistory = try await CloudAIProxyClient.shared.currentUsageGenerations()
            lastErrorMessage = nil
        } catch {
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
