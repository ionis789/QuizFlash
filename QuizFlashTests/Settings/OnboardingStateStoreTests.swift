//
//  OnboardingStateStoreTests.swift
//  QuizFlashTests
//
//  Covers first-account onboarding state persistence.
//

import XCTest
@testable import QuizFlash

@MainActor
final class OnboardingStateStoreTests: XCTestCase {

    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "OnboardingStateStoreTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        suiteName = nil
        userDefaults = nil
        super.tearDown()
    }

    func testNewAccountIsPendingUntilRequiredOnboardingCompletes() {
        let store = OnboardingStateStore(userDefaults: userDefaults)
        let user = AuthUserSnapshot(
            uid: "new-user",
            email: "new@example.com",
            displayName: nil,
            photoURLString: nil,
            providers: [AuthProviderID.password.rawValue],
            isEmailVerified: true
        )

        store.markPendingForNewAccount(uid: user.uid)
        store.presentRequiredIfNeeded(for: user)

        XCTAssertEqual(store.presentation, .required(uid: user.uid))
        XCTAssertTrue(store.hasPendingOnboarding(for: user.uid))
        XCTAssertFalse(store.hasCompletedOnboarding(for: user.uid))

        store.complete(.required(uid: user.uid))

        XCTAssertNil(store.presentation)
        XCTAssertFalse(store.hasPendingOnboarding(for: user.uid))
        XCTAssertTrue(store.hasCompletedOnboarding(for: user.uid))
    }

    func testPreviewCompletionDoesNotPersistAccountCompletion() {
        let store = OnboardingStateStore(userDefaults: userDefaults)

        store.presentPreview()
        guard let presentation = store.presentation else {
            return XCTFail("Expected preview presentation.")
        }

        store.complete(presentation)

        XCTAssertNil(store.presentation)
        XCTAssertFalse(store.hasCompletedOnboarding(for: "preview-user"))
        XCTAssertFalse(store.hasPendingOnboarding(for: "preview-user"))
    }
}
