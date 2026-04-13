//
//  ThemeManagerTests.swift
//  QuizFlashTests
//
//  Covers the fixed application theme configuration.
//

import XCTest
@testable import QuizFlash

final class ThemeManagerTests: XCTestCase {
    func testThemeManagerUsesFixedBrandAccent() {
        let suiteName = "ThemeManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let manager = ThemeManager(userDefaults: defaults)
        let reloadedManager = ThemeManager(userDefaults: defaults)

        XCTAssertEqual(manager.accentColor, .brand)
        XCTAssertEqual(reloadedManager.accentColor, .brand)
    }

    func testThemeManagerPersistsColorOverrides() {
        let suiteName = "ThemeManagerOverrideTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let manager = ThemeManager(userDefaults: defaults)
        manager.setColorHexOverride("#FF5A5F", for: .dangerPrimary)

        let reloadedManager = ThemeManager(userDefaults: defaults)

        XCTAssertEqual(reloadedManager.resolvedHex(for: .dangerPrimary), "#FF5A5F")
        XCTAssertTrue(reloadedManager.hasColorOverride(for: .dangerPrimary))
    }

    func testThemeManagerCanResetColorOverrides() {
        let suiteName = "ThemeManagerResetTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let manager = ThemeManager(userDefaults: defaults)
        let defaultHex = manager.defaultHex(for: .brandPrimary)

        manager.setColorHexOverride("#AA77FF", for: .brandPrimary)
        manager.clearColorOverride(for: .brandPrimary)

        XCTAssertEqual(manager.resolvedHex(for: .brandPrimary), defaultHex)
        XCTAssertFalse(manager.hasColorOverride(for: .brandPrimary))
    }

    func testThemeManagerPersistsRoleOverrides() {
        let suiteName = "ThemeManagerRoleOverrideTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let manager = ThemeManager(userDefaults: defaults)
        manager.setRoleOverride(.dangerPrimary, for: .buttonPrimaryFill)

        let reloadedManager = ThemeManager(userDefaults: defaults)

        XCTAssertEqual(reloadedManager.resolvedToken(for: .buttonPrimaryFill), .dangerPrimary)
        XCTAssertTrue(reloadedManager.hasRoleOverride(for: .buttonPrimaryFill))
    }
}
