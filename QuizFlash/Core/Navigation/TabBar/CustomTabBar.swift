//
//  CustomTabBar.swift
//  QuizFlash
//
//  SwiftUI-owned tab bar UI backed by a UIKit capsule animator.
//

import SwiftUI

/// The floating app tab bar.
///
/// SwiftUI owns the visual layout so the bar can be restyled locally, while a
/// UIKit-backed capsule animator keeps the selection motion smooth when the
/// destination `TabView` screen is expensive to render.
struct CustomTabBar: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    let activeTab: AppTabBar
    var onTabSelection: (AppTabBar) -> Void

    private var inactiveColor: Color {
        themeManager.roleColor(.tabUnselectedForeground)
    }

    private var selectedColor: Color {
        themeManager.brandPrimary
    }

    var body: some View {
        CapsuleSelectionControl(
            options: AppTabBar.visibleTabs,
            selection: activeTab,
            onSelection: onTabSelection,
            onReselect: onTabSelection
        ) { tab, isSelected in
            Image(systemName: tab.symbol)
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .symbolVariant(.fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
                .foregroundStyle(isSelected ? selectedColor : inactiveColor)
                .accessibilityLabel(tab.localizedTitle(locale: appPreferences.resolvedLocale))
        }
        .frame(height: UIConstants.Size.bottomChromeBarHeight)
        .padding(.horizontal, 22)
        .ignoresSafeArea(.container, edges: .bottom)
    }
}
