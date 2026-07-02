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
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss

    let safeAreaInsets: UIEdgeInsets
    let onPhotos: () -> Void
    let onPDF: () -> Void

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    private func dismissThen(_ action: @escaping () -> Void) {
        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss(completion: action)
        } else {
            action()
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            sourceButton(
                title: localized("Choose Photos"),
                systemImage: "photo.on.rectangle.angled",
                action: { dismissThen(onPhotos) }
            )

            sourceButton(
                title: localized("Choose PDF"),
                systemImage: "doc.richtext.fill",
                action: { dismissThen(onPDF) }
            )
        }
        .padding(.horizontal, UIConstants.Layout.heroScreenEdgeInset)
        .padding(.top, 28)
        .padding(.bottom, max(safeAreaInsets.bottom, 24))
        .frame(maxWidth: UIConstants.isPad ? 620 : .infinity, maxHeight: .infinity, alignment: .center)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func sourceButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: UIConstants.Spacing.medium) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(themeManager.roleColor(.labelPrimaryForeground))
                    .frame(width: 40, height: 40)

                Text(title)
                    .font(.system(size: 23, weight: .heavy))
                    .foregroundStyle(themeManager.roleColor(.labelPrimaryForeground))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, UIConstants.Spacing.large)
            .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
        .duoPressableSurfaceStyle()
        .primarySelectionSurface(cornerRadius: 32)
    }
}
