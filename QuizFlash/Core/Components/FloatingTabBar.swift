//
//  FloatingTabBar.swift
//  QuizFlash
//
//  Created by Ion Socol on 23.12.2025.
//

import SwiftUI

struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab

    // Pentru animatia de alunecare de la un menu la altul
    @Namespace private var animationNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20))
                        Text(tab.title)
                            .font(.caption2.bold())
                    }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(selectedTab == tab ? .accent : .gray)
                    .background {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 60)
                                .fill(.black.opacity(0.3))
                                .shadow(color: .white.opacity(0.1), radius: 4, x: 0, y: 2)
                            // Animatia de slide de la un menu la altu
                            .matchedGeometryEffect(id: "activeTabBackground", in: animationNamespace)
                        }
                    }
                }
            }
        }
            .padding(3)
            .background {
            Capsule()
                .fill(.ultraThinMaterial)
            .shadow(color: .white.opacity(0.1), radius: 2, x: 0, y: 0)
        }
            .padding(.horizontal, 54)
    }
}
