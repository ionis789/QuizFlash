//
//  AppPreferences.swift
//  QuizFlash
//
//  App-wide lightweight preferences backed by UserDefaults.
//

import Foundation
import Observation

// MARK: - Week Start Preference

/// Controls which weekday anchors the Home calendar grid.
nonisolated enum AppWeekStartDayPreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case monday
    case sunday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System Default"
        case .monday:
            return "Monday"
        case .sunday:
            return "Sunday"
        }
    }

    var resolvedCalendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        switch self {
        case .system:
            break
        case .monday:
            calendar.firstWeekday = 2
        case .sunday:
            calendar.firstWeekday = 1
        }
        return calendar
    }
}

// MARK: - Create Deck Sort Preference

/// Persists the default presentation order for draft cards in Create Deck.
nonisolated enum CreateDeckSortOrder: String, CaseIterable, Identifiable, Codable, Sendable {
    case newest
    case oldest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest:
            return "Newest First"
        case .oldest:
            return "Oldest First"
        }
    }
}

// MARK: - App Preferences Store

/// Shared app preferences consumed by Home, Create Deck, and Settings surfaces.
@Observable
@MainActor
final class AppPreferences {
    static let shared = AppPreferences()

    private enum Keys {
        static let weekStartDay = "preferences.calendar.weekStartDay"
        static let createDeckSortOrder = "preferences.createDeck.sortOrder"
        static let autoCollapseEarlierCards = "preferences.createDeck.autoCollapseEarlierCards"
    }

    private let userDefaults: UserDefaults

    /// Preferred first day of the week for calendar surfaces.
    var weekStartDay: AppWeekStartDayPreference {
        didSet {
            userDefaults.set(weekStartDay.rawValue, forKey: Keys.weekStartDay)
        }
    }

    /// Default sort applied when the Create Deck editor renders draft cards.
    var createDeckSortOrder: CreateDeckSortOrder {
        didSet {
            userDefaults.set(createDeckSortOrder.rawValue, forKey: Keys.createDeckSortOrder)
        }
    }

    /// When enabled, AI sessions start with historical cards collapsed by default.
    var autoCollapseEarlierCardsInAISession: Bool {
        didSet {
            userDefaults.set(
                autoCollapseEarlierCardsInAISession,
                forKey: Keys.autoCollapseEarlierCards
            )
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.weekStartDay = AppWeekStartDayPreference(
            rawValue: userDefaults.string(forKey: Keys.weekStartDay) ?? ""
        ) ?? .system
        self.createDeckSortOrder = CreateDeckSortOrder(
            rawValue: userDefaults.string(forKey: Keys.createDeckSortOrder) ?? ""
        ) ?? .newest
        self.autoCollapseEarlierCardsInAISession = userDefaults.object(
            forKey: Keys.autoCollapseEarlierCards
        ) as? Bool ?? true
    }

    /// Resolves the app's effective calendar based on the stored weekday preference.
    var resolvedCalendar: Calendar {
        weekStartDay.resolvedCalendar
    }
}
