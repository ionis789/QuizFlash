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
    private let iconSize: CGFloat = UIConstants.Size.actionButton

    // MARK: - View

    var body: some View {
        Button {
            router.append(AppRoute.settings)
        } label: {
            ZStack {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .padding(2.5)
            }
            .frame(width: iconSize, height: iconSize)
            .glassButton(shape: .circle)
        }
        .buttonStyle(.plain)
    }
}
