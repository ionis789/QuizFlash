//
//  CollapsibleTitleChrome.swift
//  QuizFlash
//
//  Shared large-title chrome that reveals a centered floating title once the
//  hero title scrolls out of view.
//

import SwiftUI

// MARK: - Collapsible Title Metrics

enum CollapsibleTitleChromeMetrics {
    static let hiddenScale: CGFloat = 0.82
    static let floatingTitleVerticalOffset: CGFloat =  0
    static let visibilityAnimation = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let shadowFadeAnimation = Animation.easeInOut(duration: 0.22)
}

// MARK: - Collapsible Title Label

struct CollapsibleTitlePill: View {
    let title: AppTextValue
    let maxWidth: CGFloat
    let isVisible: Bool
    var animateVisibility = true
    var fallbackTitle: String = ""
    var visibilityAnimation: Animation? = nil
    var coordinateSpaceName: String? = nil
    var onContentFrameChange: ((CGRect) -> Void)? = nil

    init(
        title: AppTextValue,
        maxWidth: CGFloat,
        isVisible: Bool,
        animateVisibility: Bool = true,
        fallbackTitle: String = "",
        visibilityAnimation: Animation? = nil,
        coordinateSpaceName: String? = nil,
        onContentFrameChange: ((CGRect) -> Void)? = nil
    ) {
        self.title = title
        self.maxWidth = maxWidth
        self.isVisible = isVisible
        self.animateVisibility = animateVisibility
        self.fallbackTitle = fallbackTitle
        self.visibilityAnimation = visibilityAnimation
        self.coordinateSpaceName = coordinateSpaceName
        self.onContentFrameChange = onContentFrameChange
    }

    private var resolvedVerbatimTitle: String {
        switch title {
        case .localized:
            return fallbackTitle
        case .verbatim(let rawTitle):
            let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? fallbackTitle : trimmed
        }
    }

    private var hasTitle: Bool {
        switch title {
        case .localized:
            return true
        case .verbatim:
            return !resolvedVerbatimTitle.isEmpty
        }
    }

    var body: some View {
        AppTextLabel(value: titleForRendering)
            .font(.system(size: 18, weight: .black))
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.86)
            .frame(maxWidth: maxWidth)
            .shadow(color: .black.opacity(0.92), radius: 18, x: 0, y: 0)
            .shadow(color: .black.opacity(0.85), radius: 7, x: 0, y: 1)
            .shadow(color: .black.opacity(0.7), radius: 1.5, x: 0, y: 0)
            .opacity(hasTitle ? 1 : 0)
            .frame(height: UIConstants.Size.capsuleHeight)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : CollapsibleTitleChromeMetrics.hiddenScale, anchor: .top)
        .animation(
            animateVisibility
                ? (visibilityAnimation ?? CollapsibleTitleChromeMetrics.visibilityAnimation)
                : nil,
            value: isVisible
        )
        .overlay {
            if isVisible, hasTitle, let coordinateSpaceName {
                Color.clear
                    .allowsHitTesting(false)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(coordinateSpaceName))
                    } action: { newFrame in
                        onContentFrameChange?(newFrame)
                    }
            }
        }
        .accessibilityLabel(resolvedVerbatimTitle)
    }

    private var titleForRendering: AppTextValue {
        switch title {
        case .localized:
            return title
        case .verbatim:
            return .verbatim(resolvedVerbatimTitle)
        }
    }
}

// MARK: - Collapsible Title Navigation Bar

struct CollapsibleTitleNavigationBar<Leading: View, Center: View, Trailing: View>: View {
    let coordinateSpaceName: String
    let horizontalInset: CGFloat
    let appliesTopNavigationChrome: Bool
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
        appliesTopNavigationChrome: Bool = true,
        onHeightChange: @escaping (CGFloat) -> Void = { _ in },
        onBottomChange: @escaping (CGFloat) -> Void = { _ in },
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder center: @escaping (CGFloat) -> Center,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.coordinateSpaceName = coordinateSpaceName
        self.horizontalInset = horizontalInset
        self.appliesTopNavigationChrome = appliesTopNavigationChrome
        self.onHeightChange = onHeightChange
        self.onBottomChange = onBottomChange
        self.leading = leading
        self.center = center
        self.trailing = trailing
    }

    var body: some View {
        chromeContent
            .modifier(
                CollapsibleTitleTopChromeModifier(
                    appliesTopNavigationChrome: appliesTopNavigationChrome,
                    horizontalInset: horizontalInset
                )
            )
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

    private var chromeContent: some View {
        GeometryReader { proxy in
            let availableWidth = max(0, proxy.size.width - (horizontalInset * 2))
            let sideReserve = max(leadingControlWidth, trailingControlWidth)
            let maxCenterWidth = max(
                UIConstants.Size.capsuleHeight,
                availableWidth - (sideReserve * 2) - (UIConstants.Spacing.medium * 2)
            )

            ZStack(alignment: .center) {
                center(maxCenterWidth)
                    .offset(y: CollapsibleTitleChromeMetrics.floatingTitleVerticalOffset)
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
    }
}

private struct CollapsibleTitleTopChromeModifier: ViewModifier {
    let appliesTopNavigationChrome: Bool
    let horizontalInset: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if appliesTopNavigationChrome {
            content.topNavigationChrome(horizontalInset: horizontalInset)
        } else {
            content
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
                .font(.system(size: UIConstants.Size.circularChromeSymbol, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
        }
        .buttonStyle(.plain)
    }
}

/// Shared soft-circle symbol button used by dismiss and lightweight utility actions.
struct ChromeSoftCircleSymbolButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void
    var size: CGFloat = UIConstants.Size.actionButton
    var tint: Color? = nil
    var backgroundTint: Color? = nil

    var body: some View {
        Button(action: action) {
            ChromeSoftCircleSymbol(
                systemName: systemName,
                size: size,
                tint: tint,
                backgroundTint: backgroundTint
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Shared soft-circle glyph that keeps the dark circular background and lavender icon treatment reusable.
struct ChromeSoftCircleSymbol: View {
    @Environment(ThemeManager.self) private var themeManager

    let systemName: String
    let size: CGFloat
    var tint: Color? = nil
    var backgroundTint: Color? = nil

    private var resolvedTint: Color {
        tint ?? themeManager.roleColor(.circularToolbarForeground)
    }

    private var resolvedBackgroundTint: Color {
        backgroundTint ?? themeManager.roleColor(.circularToolbarFill)
    }

    private var symbolSize: CGFloat {
        min(UIConstants.Size.circularChromeSymbol, max(UIConstants.Size.iconSmall, size * 0.44))
    }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: symbolSize, weight: .bold))
            .foregroundStyle(resolvedTint)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(resolvedBackgroundTint)
            }
            .shadow(color: .black.opacity(0.30), radius: 10, x: 0, y: 5)
            .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
            .contentShape(Circle())
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
    let title: AppTextValue

    init(title: AppTextValue) {
        self.title = title
    }
    var body: some View {
        AppTextLabel(value: title)
            .font(.system(size: 40, weight: .black))
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
