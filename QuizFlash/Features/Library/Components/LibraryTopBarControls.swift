//
//  LibraryTopBarControls.swift
//  QuizFlash
//
//  Visual building blocks used by the Library top chrome.
//

import SwiftUI
import UIKit

// MARK: - Top Bar Button Style

struct LibraryTopBarNoHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// MARK: - Top Bar Metrics

enum LibraryTopBarChromeMetrics {
    static let expandedHitTargetSize = UIConstants.Size.actionButton + 16
    static let searchFieldRevealThreshold: CGFloat = 0.18
}

// MARK: - Search Glyph

struct LibraryTopBarSearchGlyph: View {
    let color: Color

    var body: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: UIConstants.Size.actionIcon, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: UIConstants.Size.actionIcon, height: UIConstants.Size.actionIcon)
    }
}

// MARK: - Search Icon Button

struct LibraryTopBarSearchIconButton: View {
    @Environment(AppPreferences.self) private var appPreferences
    let action: () -> Void
    private let hitTargetSize = LibraryTopBarChromeMetrics.expandedHitTargetSize

    var body: some View {
        ChromeSoftCircleSymbolButton(
            systemName: "magnifyingglass",
            accessibilityLabel: AppLocalization.string("Search", locale: appPreferences.resolvedLocale),
            action: action
        )
        .frame(width: hitTargetSize, height: hitTargetSize)
        .contentShape(Circle())
    }
}

// MARK: - Search Field Background

struct LibraryTopBarSearchFieldBackground: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        Capsule()
            .fill(themeManager.roleColor(.buttonSurfaceFill))
            .shadow(color: Color.black.opacity(0.24), radius: 18, y: 10)
    }
}

// MARK: - Trailing Accessory

struct LibraryTopBarTrailingAccessory: View {
    @Environment(AppPreferences.self) private var appPreferences
    let searchText: String
    let isSearchFocused: Bool
    let clearAction: () -> Void

    var body: some View {
        if searchText.isEmpty {
            EmptyView()
        } else {
            ChromeSoftCircleSymbolButton(
                systemName: "xmark",
                accessibilityLabel: AppLocalization.string("Clear search text", locale: appPreferences.resolvedLocale),
                action: clearAction,
                size: 28,
                symbolSize: 17
            )
        }
    }
}

// MARK: - More Settings Button

struct LibraryTopBarMoreSettingsButton: View {
    @Environment(AppPreferences.self) private var appPreferences
    private let menu: (@escaping () -> Void, @escaping () -> Void) -> UIMenu
    let isSelecting: Bool
    let onDoneSelecting: () -> Void
    private let hitTargetSize = LibraryTopBarChromeMetrics.expandedHitTargetSize

    init(
        isSelecting: Bool = false,
        onDoneSelecting: @escaping () -> Void = {},
        menu: @escaping (@escaping () -> Void, @escaping () -> Void) -> UIMenu
    ) {
        self.isSelecting = isSelecting
        self.onDoneSelecting = onDoneSelecting
        self.menu = menu
    }

    var body: some View {
        SelectionModeMenuButton(
            isSelecting: isSelecting,
            menuAccessibilityLabel: AppLocalization.string("More library actions", locale: appPreferences.resolvedLocale),
            doneAccessibilityLabel: AppLocalization.string("Done selecting decks", locale: appPreferences.resolvedLocale),
            onDone: onDoneSelecting,
            menu: menu
        )
        .frame(width: hitTargetSize, height: hitTargetSize)
        .contentShape(Circle())
    }
}

struct LibraryTopBarDismissSearchButton: View {
    @Environment(AppPreferences.self) private var appPreferences
    let action: () -> Void

    private let hitTargetSize = LibraryTopBarChromeMetrics.expandedHitTargetSize

    var body: some View {
        ChromeSoftCircleSymbolButton(
            systemName: "xmark",
            accessibilityLabel: AppLocalization.string("Close search", locale: appPreferences.resolvedLocale),
            action: action
        )
        .frame(width: hitTargetSize, height: hitTargetSize)
        .contentShape(Circle())
    }
}

// MARK: - Back Button

struct LibraryTopBarBackButton: View {
    @Environment(ThemeManager.self) private var themeManager

    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.compact.left")
                    .font(.system(size: UIConstants.Size.navigationChromeIcon, weight: .bold))
                    .fontDesign(.rounded)
                Text(label)
                    .font(.system(size: UIConstants.Size.navigationChromeLabel, weight: .bold))
                    .fontDesign(.rounded)
            }
            .foregroundStyle(themeManager.roleColor(.backButtonForeground))
            .fixedSize(horizontal: true, vertical: false)
        }
        .quizFlashButtonStyle(.surface, shape: .capsule, size: UIConstants.Size.capsuleHeight)
    }
}

// MARK: - Voice Glyph

struct LibraryVoiceCommandGlyph: View {
    let isActive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            Capsule().frame(width: 3, height: 9)
            Capsule().frame(width: 3, height: 14)
            Capsule().frame(width: 3, height: 11)
        }
        .foregroundStyle(isActive ? .primary : .secondary)
        .frame(width: 28, height: 28)
        .background {
            Circle()
                .fill(Color(uiColor: .tertiarySystemFill))
        }
        .scaleEffect(isActive ? 1.02 : 1)
        .animation(.easeInOut(duration: UIConstants.Animation.instant), value: isActive)
    }
}
