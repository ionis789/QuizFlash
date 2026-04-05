//
//  LibraryTopBarControls.swift
//  QuizFlash
//
//  Visual building blocks used by the Library top chrome.
//

import SwiftUI

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

private struct LibraryTopBarGlassCircleShell: View {
    var body: some View {
        Circle()
            .fill(.clear)
            .glassButton(shape: .circle)
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
    }
}

// MARK: - Search Icon Button

struct LibraryTopBarSearchIconButton: View {
    let accent: Color
    let action: () -> Void
    private let hitTargetSize = LibraryTopBarChromeMetrics.expandedHitTargetSize

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.clear
                    .frame(width: hitTargetSize, height: hitTargetSize)

                LibraryTopBarGlassCircleShell()

                LibraryTopBarSearchGlyph(color: accent)
            }
            .frame(width: hitTargetSize, height: hitTargetSize)
            .contentShape(Circle())
        }
        .buttonStyle(LibraryTopBarNoHighlightButtonStyle())
        .contentShape(Circle())
        .accessibilityLabel("Search")
    }
}

// MARK: - Trailing Mode Controls

private struct LibraryTopBarTrailingModeGlyph: View {
    let systemName: String
    let accent: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: UIConstants.Size.actionIcon, weight: .bold))
            .foregroundStyle(accent)
    }
}

struct LibraryTopBarTrailingControlShell: View {
    let accent: Color
    let glyphName: String
    let hitTargetSize: CGFloat

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: hitTargetSize, height: hitTargetSize)

            LibraryTopBarGlassCircleShell()

            LibraryTopBarTrailingModeGlyph(
                systemName: glyphName,
                accent: accent
            )
        }
        .frame(
            width: UIConstants.Size.actionButton,
            height: UIConstants.Size.actionButton
        )
        .frame(width: hitTargetSize, height: hitTargetSize)
        .contentShape(Circle())
    }
}

// MARK: - Search Field Background

struct LibraryTopBarSearchFieldBackground: View {
    var body: some View {
        Capsule()
            .fill(.clear)
            .glassButton(shape: .capsule)
    }
}

// MARK: - Trailing Accessory

struct LibraryTopBarTrailingAccessory: View {
    let searchText: String
    let isSearchFocused: Bool
    let clearAction: () -> Void

    var body: some View {
        if searchText.isEmpty {
            EmptyView()
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
            .buttonStyle(LibraryTopBarNoHighlightButtonStyle())
            .accessibilityLabel("Clear search text")
        }
    }
}

// MARK: - More Settings Button

struct LibraryTopBarMoreSettingsButton<MenuContent: View>: View {
    let accent: Color
    private let menuContent: () -> MenuContent
    private let hitTargetSize = LibraryTopBarChromeMetrics.expandedHitTargetSize

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
            Circle()
                .fill(Color.black.opacity(0.001))
                .frame(width: hitTargetSize, height: hitTargetSize)
        }
        .buttonStyle(LibraryTopBarNoHighlightButtonStyle())
        .frame(width: hitTargetSize, height: hitTargetSize)
        .contentShape(Circle())
        .overlay {
            LibraryTopBarTrailingControlShell(
                accent: accent,
                glyphName: "ellipsis",
                hitTargetSize: hitTargetSize
            )
            .allowsHitTesting(false)
        }
    }
}

struct LibraryTopBarDismissSearchButton: View {
    let accent: Color
    let action: () -> Void

    private let hitTargetSize = LibraryTopBarChromeMetrics.expandedHitTargetSize

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.black.opacity(0.001))
                .frame(width: hitTargetSize, height: hitTargetSize)
        }
        .buttonStyle(LibraryTopBarNoHighlightButtonStyle())
        .overlay {
            LibraryTopBarTrailingControlShell(
                accent: accent,
                glyphName: "xmark",
                hitTargetSize: hitTargetSize
            )
            .frame(width: hitTargetSize, height: hitTargetSize)
            .contentShape(Circle())
            .allowsHitTesting(false)
        }
        .frame(width: hitTargetSize, height: hitTargetSize)
        .contentShape(Circle())
        .accessibilityLabel("Close search")
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
