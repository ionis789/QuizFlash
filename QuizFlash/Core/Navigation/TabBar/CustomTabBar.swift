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
    let activeTab: AppTabBar
    var onTabSelection: (AppTabBar) -> Void

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    var body: some View {
        CapsuleSelectionControl(
            options: AppTabBar.allCases,
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
            .foregroundStyle(isSelected ? accent : Color.primary)
        }
        .frame(height: UIConstants.Size.bottomChromeBarHeight)
        .padding(.horizontal, 25)
        .ignoresSafeArea(.container, edges: .bottom)
    }
}
