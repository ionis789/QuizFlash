//
//  ThemeManagerTests.swift
//  QuizFlashTests
//
//  Covers theme selection persistence backed by UserDefaults.
//

import XCTest
@testable import QuizFlash

final class ThemeManagerTests: XCTestCase {
    func testThemeManagerPersistsAccentSelection() {
        let suiteName = "ThemeManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let manager = ThemeManager(userDefaults: defaults)
        manager.accentColor = .green

        let reloadedManager = ThemeManager(userDefaults: defaults)
        XCTAssertEqual(reloadedManager.accentColor, .green)
    }
}
