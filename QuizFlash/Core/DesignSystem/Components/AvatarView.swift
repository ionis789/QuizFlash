//
//  AvatarView.swift
//  QuizFlash
//
//  Created by Ion Socol on 07.03.2026.
//

import SwiftUI

/// A circular avatar button that navigates to the Settings screen.
struct HomeAvatarView: View {


    /// The global navigation router.
    let router: NavigationManager

    /// The fixed dimension for the profile avatar button.
    private let iconSize: CGFloat = 54.0

    var body: some View {
        Button {
            router.append(AppRoute.settings)
        } label: {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .systemBackground))
                    .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)

                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)

                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .padding(2.5)
            }
                .frame(width: iconSize, height: iconSize)
        }
    }
}


