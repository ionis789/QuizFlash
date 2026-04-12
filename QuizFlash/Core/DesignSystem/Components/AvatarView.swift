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
    var iconSize: CGFloat = UIConstants.Size.actionButton

    // MARK: - View

    var body: some View {
        Button {
            router.append(AppRoute.settings)
        } label: {
            Image(systemName: "person")
                .font(.system(size: iconSize * 0.44, weight: .regular))
                .foregroundStyle(Color.primary.opacity(0.88))
                .symbolRenderingMode(.hierarchical)
                .frame(width: iconSize, height: iconSize)
        }
        .buttonStyle(.plain)
    }
}
