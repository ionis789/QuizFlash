//
//  DeckWorkspaceOptionPickerSheetView.swift
//  QuizFlash
//
//  Shared compact option picker used by deck-workspace sheets.
//

import SwiftUI

struct DeckWorkspaceOptionPickerItem {
    let id: String
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void
}

struct DeckWorkspaceOptionPickerSheetView: View {
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss

    let safeAreaInsets: UIEdgeInsets
    let items: [DeckWorkspaceOptionPickerItem]

    var body: some View {
        VStack(spacing: 18) {
            ForEach(items, id: \.id) { item in
                optionButton(item)
            }
        }
        .padding(.horizontal, UIConstants.Layout.heroScreenEdgeInset)
        .padding(.top, 28)
        .padding(.bottom, max(safeAreaInsets.bottom, 24))
        .frame(maxWidth: UIConstants.isPad ? 620 : .infinity, maxHeight: .infinity, alignment: .center)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func optionButton(_ item: DeckWorkspaceOptionPickerItem) -> some View {
        Button {
            dismissThen(item.action)
        } label: {
            HStack(spacing: UIConstants.Spacing.medium) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(item.tint)
                    .frame(width: 40, height: 40)

                Text(item.title)
                    .font(.system(size: 23, weight: .heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, UIConstants.Spacing.large)
            .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
        .duoPressableSurfaceStyle()
        .duoSurface(cornerRadius: 32, tint: item.tint)
    }

    private func dismissThen(_ action: @escaping () -> Void) {
        if let fullScreenSheetDismiss {
            fullScreenSheetDismiss(completion: action)
        } else {
            action()
        }
    }
}

struct ManualCardTypePickerSheetView: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    let safeAreaInsets: UIEdgeInsets
    let onSelect: (CardKind) -> Void

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
                    id: CardKind.flashcard.rawValue,
                    title: localized("Flashcard"),
                    systemImage: "rectangle.portrait.on.rectangle.portrait.angled",
                    tint: accent,
                    action: { onSelect(.flashcard) }
                ),
                DeckWorkspaceOptionPickerItem(
                    id: CardKind.quiz.rawValue,
                    title: localized("Quiz"),
                    systemImage: "questionmark.square.dashed",
                    tint: .orange,
                    action: { onSelect(.quiz) }
                ),
            ]
        )
    }
}
