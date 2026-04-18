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
            VStack(spacing: 6) {
                Image(systemName: tab.symbol)
                    .font(.title2)
                    .symbolVariant(.fill)

                Text(tab.title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            .foregroundStyle(isSelected ? selectedColor : inactiveColor)
        }
        .frame(height: UIConstants.Size.bottomChromeBarHeight)
        .padding(.horizontal, 25)
        .ignoresSafeArea(.container, edges: .bottom)
    }
}
