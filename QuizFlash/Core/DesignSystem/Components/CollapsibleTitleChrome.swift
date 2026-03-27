//
//  CollapsibleTitleChrome.swift
//  QuizFlash
//
//  Shared large-title chrome that reveals a centered capsule once the hero
//  title scrolls out of view.
//

import SwiftUI

// MARK: - Collapsible Title Metrics

enum CollapsibleTitleChromeMetrics {
    static let maximumPillWidth: CGFloat = 220
    static let hiddenScale: CGFloat = 0.82
}

// MARK: - Collapsible Title Pill

struct CollapsibleTitlePill: View {
    let title: String
    let maxWidth: CGFloat
    let isVisible: Bool
    var fallbackTitle: String = ""

    @State private var measuredTextWidth: CGFloat = 0

    private var resolvedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return fallbackTitle
        }
        return trimmed
    }

    private var hasTitle: Bool {
        !resolvedTitle.isEmpty
    }

    private var horizontalPadding: CGFloat {
        hasTitle ? UIConstants.Spacing.standard : 0
    }

    private var resolvedWidth: CGFloat {
        let intrinsicWidth = measuredTextWidth + (horizontalPadding * 2)
        let cappedMaxWidth = min(maxWidth, CollapsibleTitleChromeMetrics.maximumPillWidth)
        return min(cappedMaxWidth, max(UIConstants.Size.buttonHeight, intrinsicWidth))
    }

    var body: some View {
        ZStack {
            if hasTitle {
                Text(resolvedTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { newWidth in
                        if abs(measuredTextWidth - newWidth) > 0.5 {
                            measuredTextWidth = newWidth
                        }
                    }
            }

            Text(resolvedTitle)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.92)
                .frame(width: max(0, resolvedWidth - (horizontalPadding * 2)))
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, UIConstants.Spacing.small)
        .frame(width: resolvedWidth)
        .frame(height: UIConstants.Size.capsuleHeight)
        .glassButton(shape: .capsule)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : CollapsibleTitleChromeMetrics.hiddenScale, anchor: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isVisible)
        .accessibilityLabel(resolvedTitle.isEmpty ? fallbackTitle : resolvedTitle)
    }
}

// MARK: - Collapsible Title Navigation Bar

struct CollapsibleTitleNavigationBar<Leading: View, Center: View, Trailing: View>: View {
    let coordinateSpaceName: String
    let horizontalInset: CGFloat
    let onHeightChange: (CGFloat) -> Void
    let onBottomChange: (CGFloat) -> Void
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let center: (CGFloat) -> Center
    @ViewBuilder let trailing: () -> Trailing

    @State private var leadingControlWidth: CGFloat = UIConstants.Size.actionButton
    @State private var trailingControlWidth: CGFloat = UIConstants.Size.actionButton

    init(
        coordinateSpaceName: String,
        horizontalInset: CGFloat = UIConstants.Layout.compactScreenEdgeInset,
        onHeightChange: @escaping (CGFloat) -> Void,
        onBottomChange: @escaping (CGFloat) -> Void,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder center: @escaping (CGFloat) -> Center,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.coordinateSpaceName = coordinateSpaceName
        self.horizontalInset = horizontalInset
        self.onHeightChange = onHeightChange
        self.onBottomChange = onBottomChange
        self.leading = leading
        self.center = center
        self.trailing = trailing
    }

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = max(0, proxy.size.width - (horizontalInset * 2))
            let sideReserve = max(leadingControlWidth, trailingControlWidth)
            let maxCenterWidth = max(
                UIConstants.Size.capsuleHeight,
                availableWidth - (sideReserve * 2) - (UIConstants.Spacing.medium * 2)
            )

            ZStack(alignment: .center) {
                center(maxCenterWidth)
                    .allowsHitTesting(false)

                HStack(alignment: .center) {
                    leading()
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.width
                        } action: { newWidth in
                            if abs(leadingControlWidth - newWidth) > 0.5 {
                                leadingControlWidth = newWidth
                            }
                        }

                    Spacer(minLength: 0)

                    trailing()
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.width
                        } action: { newWidth in
                            if abs(trailingControlWidth - newWidth) > 0.5 {
                                trailingControlWidth = newWidth
                            }
                        }
                }
            }
        }
        .frame(height: UIConstants.Size.capsuleHeight)
        .topNavigationChrome(horizontalInset: horizontalInset)
        .background {
            Color.clear
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    onHeightChange(newHeight)
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .named(coordinateSpaceName)).maxY
                } action: { newBottom in
                    onBottomChange(newBottom)
                }
        }
    }
}

// MARK: - Shared Chrome Buttons

struct ChromeCircleIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: UIConstants.Size.actionIcon, weight: .bold))
                .fontDesign(.rounded)
                .foregroundStyle(.primary)
                .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
                .glassButton(shape: .circle)
        }
        .buttonStyle(.plain)
    }
}

struct ChromeCirclePlaceholder: View {
    var body: some View {
        Color.clear
            .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
    }
}

// MARK: - Large Screen Title

struct LargeScreenTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 40, weight: .black, design: .rounded))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Reveal Anchor Modifier

private struct CollapsibleTitleRevealAnchorModifier: ViewModifier {
    let coordinateSpaceName: String
    let navigationBarBottomY: CGFloat
    let revealClearance: CGFloat
    @Binding var isVisible: Bool

    func body(content: Content) -> some View {
        content.background {
            Color.clear
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .named(coordinateSpaceName)).maxY
                } action: { maxY in
                    let revealLine = navigationBarBottomY - revealClearance
                    let shouldReveal = maxY < revealLine
                    if isVisible != shouldReveal {
                        isVisible = shouldReveal
                    }
                }
        }
    }
}

extension View {
    /// Updates a collapsed-title visibility binding based on a hero-title anchor.
    func collapsibleTitleRevealAnchor(
        in coordinateSpaceName: String,
        navigationBarBottomY: CGFloat,
        revealClearance: CGFloat = UIConstants.Layout.deckHeroPillRevealClearance,
        isVisible: Binding<Bool>
    ) -> some View {
        modifier(
            CollapsibleTitleRevealAnchorModifier(
                coordinateSpaceName: coordinateSpaceName,
                navigationBarBottomY: navigationBarBottomY,
                revealClearance: revealClearance,
                isVisible: isVisible
            )
        )
    }
}
