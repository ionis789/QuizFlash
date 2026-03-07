//
//  AvatarView.swift
//  QuizFlash
//

import SwiftUI

// MARK: - HomeAvatarView

/// A circular avatar button displayed in the home screen navigation bar.
///
/// Tapping the button appends the `AppRoute.settings` destination to the
/// current `NavigationManager` stack, pushing the Settings screen.
struct HomeAvatarView: View {

    // MARK: - Configuration

    /// The global navigation router used to push the Settings screen.
    let router: NavigationManager

    /// The fixed width and height of the avatar button.
    private let iconSize: CGFloat = 54.0

    // MARK: - View

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
