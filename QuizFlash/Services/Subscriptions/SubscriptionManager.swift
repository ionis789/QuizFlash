//
//  SubscriptionManager.swift
//  QuizFlash
//

import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
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
    private var cachedFunctions: Functions?

    @ObservationIgnored
    private var activeUID: String?

    // MARK: - Init

    init() { }

    init(firestore: Firestore, functions: Functions? = nil) {
        self.cachedFirestore = firestore
        self.cachedFunctions = functions
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
            let tokenResult = try await Auth.auth().currentUser?.getIDTokenResult(forcingRefresh: true)
            let claimPremium = tokenResult?.claims["premium"] as? Bool

            let userData = try await firestore
                .collection("users")
                .document(uid)
                .getDocument()
                .data()

            let profilePremium = userData?["premium"] as? Bool
            let profilePlan = userData?["plan"] as? String
            lastErrorMessage = nil

            if claimPremium == true {
                isPremium = true
                planSource = .firebaseCustomClaim
            } else if profilePremium == true || profilePlan == "premium" {
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

    func consumeAIGenerationQuota(targetCards: Int) async throws {
        do {
            let result = try await functions.httpsCallable("consumeAIGenerationQuota").call([
                "targetCards": targetCards
            ])

            guard let response = result.data as? [String: Any] else {
                await refresh()
                return
            }

            applyQuotaResponse(response)
        } catch {
            do {
                try await consumeAIGenerationQuotaDirectly(targetCards: targetCards)
            } catch {
                await refresh()
                throw error
            }
        }
    }

    func applyCloudAIQuotaState(_ state: CloudAIQuotaState) {
        if isPremium && !state.premium {
            freeGenerationsUsed = nil
            freeGenerationsLimit = nil
            lastErrorMessage = nil
            return
        }

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

    private func applyQuotaResponse(_ response: [String: Any]) {
        if response["premium"] as? Bool == true {
            isPremium = true
            planSource = .manualFirestore
            clearFreeQuota()
        } else {
            isPremium = false
            planSource = .free
            applyFreeQuota(
                used: response["freeGenerationsUsed"] as? Int,
                limit: response["freeGenerationsLimit"] as? Int
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
        let resolvedLimit = max(limit ?? freeGenerationsLimit ?? Self.defaultFreeGenerationsLimit, 1)
        let currentUsed = min(max(freeGenerationsUsed ?? 0, 0), resolvedLimit)
        let incomingUsed = min(max(used ?? currentUsed, 0), resolvedLimit)
        let resolvedUsed = max(currentUsed, incomingUsed)

        freeGenerationsUsed = resolvedUsed
        freeGenerationsLimit = resolvedLimit
    }

    private func consumeAIGenerationQuotaDirectly(targetCards: Int) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw SubscriptionManagerError.signInRequired
        }

        let userRef = firestore.collection("users").document(uid)
        let response: [String: Any] = try await withCheckedThrowingContinuation { continuation in
            firestore.runTransaction({ transaction, errorPointer -> Any? in
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(userRef)
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }

                let data = snapshot.data() ?? [:]
                let premium = data["premium"] as? Bool == true || data["plan"] as? String == "premium"
                let maxCards = premium ? Self.premiumMaxCardsPerGeneration : Self.freeMaxCardsPerGeneration

                guard targetCards <= maxCards else {
                    errorPointer?.pointee = SubscriptionManagerError.aiCardLimitExceeded(maximum: maxCards) as NSError
                    return nil
                }

                if premium {
                    return [
                        "premium": true
                    ]
                }

                let used = data["freeGenerationsUsed"] as? Int ?? 0
                let limit = data["freeGenerationsLimit"] as? Int ?? Self.defaultFreeGenerationsLimit

                guard used < limit else {
                    errorPointer?.pointee = SubscriptionManagerError.freeGenerationLimitReached as NSError
                    return nil
                }

                let nextUsed = used + 1
                transaction.setData([
                    "freeGenerationsUsed": nextUsed,
                    "freeGenerationsLimit": limit,
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: userRef, merge: true)

                return [
                    "premium": false,
                    "freeGenerationsUsed": nextUsed,
                    "freeGenerationsLimit": limit
                ]
            }) { object, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: object as? [String: Any] ?? [:])
                }
            }
        }

        applyQuotaResponse(response)
    }

    private var firestore: Firestore {
        if let cachedFirestore { return cachedFirestore }
        let firestore = Firestore.firestore()
        cachedFirestore = firestore
        return firestore
    }

    private var functions: Functions {
        if let cachedFunctions { return cachedFunctions }
        let functions = Functions.functions()
        cachedFunctions = functions
        return functions
    }
}

// MARK: - Subscription Plan Source

enum SubscriptionPlanSource: String, Sendable {
    case none
    case free
    case manualFirestore
    case firebaseCustomClaim

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .none:
            return AppLocalization.string("Not signed in", locale: locale)
        case .free:
            return AppLocalization.string("Free", locale: locale)
        case .manualFirestore:
            return AppLocalization.string("Manual premium", locale: locale)
        case .firebaseCustomClaim:
            return AppLocalization.string("Firebase claim", locale: locale)
        }
    }
}

// MARK: - Subscription Manager Error

enum SubscriptionManagerError: LocalizedError {
    case storeUnavailable
    case signInRequired
    case aiCardLimitExceeded(maximum: Int)
    case freeGenerationLimitReached

    var errorDescription: String? {
        switch self {
        case .storeUnavailable:
            return "Purchases are not available until App Store Connect is ready."
        case .signInRequired:
            return "Sign in is required."
        case .aiCardLimitExceeded(let maximum):
            return "This plan allows up to \(maximum) cards per generation."
        case .freeGenerationLimitReached:
            return "Free AI generation limit reached."
        }
    }
}
