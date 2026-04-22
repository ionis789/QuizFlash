//
//  CardAppearancePreferences.swift
//  QuizFlash
//
//  Card appearance preferences backed by UserDefaults.
//

import Foundation
import Observation
import SwiftUI

/// Controls how FlipCard handles content that overflows the card bounds.
nonisolated enum CardContentMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case scaleToFit = "scaleToFit"
    case scrollable = "scrollable"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scaleToFit:
            return "Scale to Fit"
        case .scrollable:
            return "Scrollable"
        }
    }

    func localizedLabel(locale: Locale) -> String {
        switch self {
        case .scaleToFit:
            return AppLocalization.string("Scale to Fit", locale: locale)
        case .scrollable:
            return AppLocalization.string("Scrollable", locale: locale)
        }
    }

    var description: String {
        switch self {
        case .scaleToFit:
            return "Content shrinks to always fit on screen. Best for quick review."
        case .scrollable:
            return "Content keeps its size and scrolls. Best for detailed notes."
        }
    }

    func localizedDescription(locale: Locale) -> String {
        switch self {
        case .scaleToFit:
            return AppLocalization.string("Content shrinks to always fit on screen. Best for quick review.",
                locale: locale
            )
        case .scrollable:
            return AppLocalization.string("Content keeps its size and scrolls. Best for detailed notes.",
                locale: locale
            )
        }
    }

    var icon: String {
        switch self {
        case .scaleToFit:
            return "arrow.up.left.and.arrow.down.right"
        case .scrollable:
            return "scroll.fill"
        }
    }
}

/// Shared appearance preferences consumed by settings and flashcard surfaces.
@Observable
@MainActor
final class CardAppearancePreferences {
    static let shared = CardAppearancePreferences()

    private enum Keys {
        static let cardContentMode = "card.contentMode"
    }

    private let userDefaults: UserDefaults

    /// Preferred overflow behaviour for flashcard content.
    var cardContentMode: CardContentMode {
        didSet {
            userDefaults.set(cardContentMode.rawValue, forKey: Keys.cardContentMode)
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.cardContentMode = CardContentMode(
            rawValue: userDefaults.string(forKey: Keys.cardContentMode) ?? ""
        ) ?? .scaleToFit
    }
}
