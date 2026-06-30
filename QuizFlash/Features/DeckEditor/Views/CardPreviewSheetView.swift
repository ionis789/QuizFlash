//
//  CardPreviewSheetView.swift
//  QuizFlash
//
//  Shared card-preview sheet chrome used by deck detail and editors.
//

import SwiftUI
import UIKit

// MARK: - Card Preview Sheet View

struct CardPreviewSheetView: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let content: DraftCardContent
    let safeAreaInsets: UIEdgeInsets
    let contentAlignment: FlashcardContentAlignment
    let textSize: FlashcardTextSize
    let showsEditButton: Bool
    let onEdit: () -> Void

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var locale: Locale { appPreferences.resolvedLocale }
    private var isQuizPreview: Bool {
        if case .quiz = content {
            return true
        }
        return false
    }

    init(
        content: DraftCardContent,
        safeAreaInsets: UIEdgeInsets,
        contentAlignment: FlashcardContentAlignment = .center,
        textSize: FlashcardTextSize = .large,
        showsEditButton: Bool = false,
        onEdit: @escaping () -> Void = {}
    ) {
        self.content = content
        self.safeAreaInsets = safeAreaInsets
        self.contentAlignment = contentAlignment
        self.textSize = textSize
        self.showsEditButton = showsEditButton
        self.onEdit = onEdit
    }

    var body: some View {
        GeometryReader { geo in
            let horizontalInset = isCompact
                ? UIConstants.Layout.compactScreenEdgeInset
                : UIConstants.Layout.screenEdgeInset

            ZStack {
                CardPreviewModeView(
                    content: content,
                    safeAreaInsets: safeAreaInsets,
                    contentAlignment: contentAlignment,
                    textSize: textSize,
                    showsQuizCloseButton: false
                )

                previewTopChrome(
                    safeTopInset: max(safeAreaInsets.top, geo.safeAreaInsets.top),
                    horizontalInset: horizontalInset
                )
            }
        }
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    private func previewTopChrome(safeTopInset: CGFloat, horizontalInset: CGFloat) -> some View {
        HStack {
            if showsEditButton {
                ChromeSoftCircleSymbolButton(
                    systemName: "pencil",
                    accessibilityLabel: localized("Edit"),
                    action: onEdit,
                    size: UIConstants.Size.actionButton
                )
            }

            if isQuizPreview {
                Button(action: dismissPreview) {
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: UIConstants.Size.actionButton)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel(localized("Close"))
            } else {
                Spacer(minLength: 0)
            }

            ChromeSoftCircleSymbolButton(
                systemName: "xmark",
                accessibilityLabel: localized("Close"),
                action: dismissPreview,
                size: UIConstants.Size.actionButton
            )
        }
        .padding(.top, safeTopInset + UIConstants.Layout.deckNavigationTopPadding)
        .padding(.horizontal, horizontalInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .zIndex(3)
    }

    private func dismissPreview() {
        fullScreenSheetDismiss?()
    }
}
