//
//  LibrarySelectionBarView.swift
//  QuizFlash
//
//  Bottom contextual bar shown during multi-select.
//  Floats above the tab bar with glass material.
//

import SwiftUI

/// A floating contextual bar displayed at the bottom of the screen during selection mode.
/// Provides actions for selected decks such as exporting or deleting.
struct LibrarySelectionBarView: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    @Bindable var viewModel: LibraryViewModel
    let decks: [DeckModel]
    let onDeleteTap: () -> Void
    var onMoveTap: (() -> Void)? = nil

    private var selectedCount: Int { viewModel.selectedDecks.count }
    private var hasSelection: Bool { selectedCount > 0 }
    private var locale: Locale { appPreferences.resolvedLocale }
    private var actionClusterBackground: some View {
        Capsule(style: .continuous)
            .fill(themeManager.roleColor(.selectionToolbarFill))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(themeManager.roleColor(.selectionToolbarBorder).opacity(0.18), lineWidth: 0.75)
            }
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    private func localizedFormat(_ value: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        let format = AppLocalization.string(value, locale: locale)
        return String(format: format, locale: locale, arguments: arguments)
    }

    var body: some View {
        HStack(spacing: 14) {

            SelectionToolbarCapsuleButton(
                action: {
                    withBottomChromeAnimation {
                        viewModel.exitSelectionMode()
                    }
                },
                accessibilityLabel: localized("Done selecting decks")
            ) {
                Text(localized("Done"))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(themeManager.textPrimary)
            }

            Spacer()

            HStack(spacing: 8) {
                SelectionToolbarIconButton(
                    isEnabled: hasSelection,
                    accessibilityLabel: localized("Move selected decks"),
                    action: { onMoveTap?() }
                ) {
                    Image(systemName: "folder")
                        .font(.system(size: UIConstants.Size.selectionToolbarIcon, weight: .semibold))
                        .foregroundStyle(hasSelection ? themeManager.textPrimary : themeManager.textSecondary)
                }

                SelectionToolbarIconButton(
                    isEnabled: hasSelection && !viewModel.isExporting,
                    accessibilityLabel: localized("Export selected decks"),
                    action: { viewModel.exportSelectedDecks(from: decks) }
                ) {
                    if viewModel.isExporting {
                        ProgressView()
                            .scaleEffect(0.78)
                            .tint(hasSelection ? themeManager.textPrimary : themeManager.textSecondary)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: UIConstants.Size.selectionToolbarIcon, weight: .semibold))
                            .foregroundStyle(hasSelection ? themeManager.textPrimary : themeManager.textSecondary)
                    }
                }

                SelectionToolbarIconButton(
                    isEnabled: hasSelection,
                    accessibilityLabel: deleteAccessibilityLabel,
                    badgeCount: selectedCount,
                    action: onDeleteTap
                ) {
                    Image(systemName: "trash")
                        .font(.system(size: UIConstants.Size.selectionToolbarIcon, weight: .semibold))
                        .foregroundStyle(hasSelection ? themeManager.dangerPrimary : themeManager.textSecondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background { actionClusterBackground }
        }
        .frame(maxWidth: .infinity)
        .animation(.selectionToolbarSpring, value: selectedCount)
    }

    private var deleteAccessibilityLabel: String {
        selectedCount == 1
            ? localizedFormat("Delete %d selected deck", selectedCount)
            : localizedFormat("Delete %d selected decks", selectedCount)
    }
}
