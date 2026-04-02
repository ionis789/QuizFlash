//
//  LibraryTopBarControls.swift
//  QuizFlash
//
//  Visual building blocks used by the Library top chrome.
//

import SwiftUI

// MARK: - Search Glyph

struct LibraryTopBarSearchGlyph: View {
    let color: Color
    let namespace: Namespace.ID
    let isSource: Bool

    var body: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: UIConstants.Size.actionIcon, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: UIConstants.Size.actionIcon, height: UIConstants.Size.actionIcon)
            .matchedGeometryEffect(
                id: "library.topbar.searchGlyph",
                in: namespace,
                isSource: isSource
            )
    }
}

// MARK: - Search Icon Button

struct LibraryTopBarSearchIconButton: View {
    let accent: Color
    let namespace: Namespace.ID
    let isSearching: Bool
    let backgroundScale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.clear)

                Circle()
                    .fill(.clear)
                    .glassButton(shape: .circle)
                    .matchedGeometryEffect(
                        id: "library.topbar.searchBackground",
                        in: namespace,
                        isSource: !isSearching
                    )
                    .frame(
                        width: UIConstants.Size.actionButton,
                        height: UIConstants.Size.actionButton
                    )
                    .scaleEffect(backgroundScale)

                LibraryTopBarSearchGlyph(
                    color: accent,
                    namespace: namespace,
                    isSource: !isSearching
                )
            }
            .frame(
                width: UIConstants.Size.actionButton,
                height: UIConstants.Size.actionButton
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel("Search")
    }
}

// MARK: - Search Field Background

struct LibraryTopBarSearchFieldBackground: View {
    let namespace: Namespace.ID
    let isSource: Bool

    var body: some View {
        Capsule()
            .fill(.clear)
            .glassButton(shape: .capsule)
            .matchedGeometryEffect(
                id: "library.topbar.searchBackground",
                in: namespace,
                isSource: isSource
            )
    }
}

// MARK: - Trailing Accessory

struct LibraryTopBarTrailingAccessory: View {
    let searchText: String
    let isSearchFocused: Bool
    let clearAction: () -> Void

    var body: some View {
        if searchText.isEmpty {
            LibraryVoiceCommandGlyph(isActive: isSearchFocused)
                .accessibilityHidden(true)
        } else {
            Button(action: clearAction) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background {
                        Circle()
                            .fill(Color(uiColor: .tertiarySystemFill))
                    }
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Clear search text")
        }
    }
}

// MARK: - More Settings Button

struct LibraryTopBarMoreSettingsButton<MenuContent: View>: View {
    let accent: Color
    private let menuContent: () -> MenuContent

    init(
        accent: Color,
        @ViewBuilder menuContent: @escaping () -> MenuContent
    ) {
        self.accent = accent
        self.menuContent = menuContent
    }

    var body: some View {
        Menu {
            menuContent()
        } label: {
            ZStack {
                Circle()
                    .fill(.clear)

                Circle()
                    .fill(.clear)
                    .glassButton(shape: .circle)
                    .frame(
                        width: UIConstants.Size.actionButton,
                        height: UIConstants.Size.actionButton
                    )

                Image(systemName: "ellipsis")
                    .font(.system(size: UIConstants.Size.actionIcon, weight: .bold))
                    .foregroundStyle(accent)
            }
            .frame(
                width: UIConstants.Size.actionButton,
                height: UIConstants.Size.actionButton
            )
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.75)
            }
            .clipShape(Circle())
            .compositingGroup()
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }
}

// MARK: - Back Button

struct LibraryTopBarBackButton: View {
    let accent: Color
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
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(height: UIConstants.Size.capsuleHeight)
            .foregroundStyle(accent)
            .glassButton(shape: .capsule)
        }
        .buttonStyle(.plain)
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
