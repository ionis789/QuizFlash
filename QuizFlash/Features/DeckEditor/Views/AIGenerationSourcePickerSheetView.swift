//
//  AIGenerationSourcePickerSheetView.swift
//  QuizFlash
//
//  Source picker shown before AI generation preparation.
//

import SwiftUI

struct AIGenerationSourcePickerSheetView: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    let safeAreaInsets: UIEdgeInsets
    let onPhotos: () -> Void
    let onPDF: () -> Void

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    private var accent: Color {
        themeManager.accentColor.color
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    var body: some View {
        DeckWorkspaceOptionPickerSheetView(
            safeAreaInsets: safeAreaInsets,
            items: [
                DeckWorkspaceOptionPickerItem(
                    id: "photos",
                    title: localized("Choose Photos"),
                    systemImage: "photo.on.rectangle.angled",
                    tint: accent,
                    action: onPhotos
                ),
                DeckWorkspaceOptionPickerItem(
                    id: "pdf",
                    title: localized("Choose PDF"),
                    systemImage: "doc.richtext.fill",
                    tint: .orange,
                    action: onPDF
                ),
            ]
        )
    }
}
