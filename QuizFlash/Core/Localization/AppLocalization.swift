//
//  AppLocalization.swift
//  QuizFlash
//
//  Shared localization helpers for app-owned copy and lightweight counted labels.
//

import Foundation
import ObjectiveC.runtime
import SwiftUI

private var kAppLocalizationBundleAssociationKey: UInt8 = 0

private final class AppLocalizedMainBundle: Bundle, @unchecked Sendable {
    override func localizedString(
        forKey key: String,
        value: String?,
        table tableName: String?
    ) -> String {
        if let overrideBundle = objc_getAssociatedObject(
            self,
            &kAppLocalizationBundleAssociationKey
        ) as? Bundle {
            return overrideBundle.localizedString(forKey: key, value: value, table: tableName)
        }

        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

enum AppTextValue: Sendable, ExpressibleByStringLiteral {
    case localized(LocalizedStringResource)
    case verbatim(String)

    init(_ resource: LocalizedStringResource) {
        self = .localized(resource)
    }

    init(verbatim value: String) {
        self = .verbatim(value)
    }

    init(stringLiteral value: String) {
        self = .localized(LocalizedStringResource(stringLiteral: value))
    }
}

struct AppTextLabel: View {
    let value: AppTextValue

    var body: some View {
        switch value {
        case .localized(let resource):
            Text(resource)
        case .verbatim(let text):
            Text(verbatim: text)
        }
    }
}

// MARK: - App Localization

enum AppLocalization {
    nonisolated static let supportedLanguageIdentifiers = ["en", "ro", "ru"]
    nonisolated private static let fallbackLanguageIdentifier = "en"

    private static let bundleOverrideInstaller: Void = {
        object_setClass(Bundle.main, AppLocalizedMainBundle.self)
    }()

    static func applyLanguageOverride(_ preference: AppLanguagePreference) {
        _ = bundleOverrideInstaller
        objc_setAssociatedObject(
            Bundle.main,
            &kAppLocalizationBundleAssociationKey,
            localizationBundle(for: preference),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    nonisolated static func string(
        _ key: String,
        locale: Locale
    ) -> String {
        let localizedBundle = localizationBundle(for: locale) ?? Bundle.main
        return localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }

    nonisolated static func string(
        _ value: String.LocalizationValue,
        locale: Locale
    ) -> String {
        String(
            localized: value,
            bundle: localizationBundle(for: locale) ?? .main,
            locale: locale
        )
    }

    nonisolated static func numbered(
        _ count: Int,
        singular: String.LocalizationValue,
        plural: String.LocalizationValue,
        locale: Locale
    ) -> String {
        let format = count == 1 ? string(singular, locale: locale) : string(plural, locale: locale)
        return String.localizedStringWithFormat(format, count)
    }

    nonisolated private static func localizationBundle(for preference: AppLanguagePreference) -> Bundle? {
        switch preference {
        case .system:
            let preferredIdentifiers = Bundle.preferredLocalizations(
                from: supportedLanguageIdentifiers,
                forPreferences: Locale.preferredLanguages
            )
            let identifier = preferredIdentifiers.first ?? fallbackLanguageIdentifier
            return localizationBundle(forIdentifier: identifier)
        case .english, .romanian, .russian:
            return localizationBundle(forIdentifier: preference.localeIdentifier)
        }
    }

    nonisolated private static func localizationBundle(for locale: Locale) -> Bundle? {
        localizationBundle(forIdentifier: locale.identifier)
    }

    nonisolated private static func localizationBundle(forIdentifier identifier: String) -> Bundle? {
        let normalizedIdentifier = identifier.replacingOccurrences(of: "_", with: "-")
        let preferredIdentifier = Bundle.preferredLocalizations(
            from: supportedLanguageIdentifiers,
            forPreferences: [normalizedIdentifier]
        ).first
        let fallbackIdentifier = normalizedIdentifier
            .components(separatedBy: "-")
            .first
        let candidates = [preferredIdentifier, fallbackIdentifier, fallbackLanguageIdentifier]
            .compactMap { $0 }

        for candidate in candidates {
            guard let bundlePath = Bundle.main.path(forResource: candidate, ofType: "lproj"),
                  let bundle = Bundle(path: bundlePath) else {
                continue
            }
            return bundle
        }

        return nil
    }
}
