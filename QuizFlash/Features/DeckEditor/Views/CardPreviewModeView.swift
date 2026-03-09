//
//  ZonePreviewSheetView.swift
//  QuizFlash
//

import SwiftUI
import UIKit

// MARK: - Card Preview Mode View

struct CardPreviewModeView: View {
    let front: ZoneCardContent
    let back: ZoneCardContent
    let safeAreaInsets: UIEdgeInsets

    @Environment(\.dismiss) private var dismiss
    @Environment(\.fullScreenSheetDismiss) private var fullScreenSheetDismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var isFlipped = false
    @State private var topChromeHeight: CGFloat = 0

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var chromeButtonHeight: CGFloat { UIConstants.Size.capsuleHeight }
    private var sideControlWidth: CGFloat { isCompact ? 88 : 104 }

    init(front: ZoneCardContent, back: ZoneCardContent, safeAreaInsets: UIEdgeInsets = .zero) {
        self.front = front
        self.back = back
        self.safeAreaInsets = safeAreaInsets
    }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let resolvedSafeTopInset    = max(safeAreaInsets.top,    geo.safeAreaInsets.top)
            let resolvedSafeBottomInset = max(safeAreaInsets.bottom, geo.safeAreaInsets.bottom)
            let headerHorizontalInset = isCompact
                ? UIConstants.Layout.compactScreenEdgeInset
                : UIConstants.Layout.screenEdgeInset
            let cardHorizontalInset = isCompact
                ? UIConstants.Spacing.standard
                : (isLandscape ? geo.size.width * 0.15 : 40)
            let cardTopInset     = topChromeHeight + UIConstants.Spacing.medium
            let cardBottomPadding = max(resolvedSafeBottomInset, UIConstants.Spacing.standard)
            let availableCardHeight = max(
                UIConstants.Size.cardMinHeight,
                geo.size.height - cardTopInset - cardBottomPadding
            )

            ZStack(alignment: .top) {
                if fullScreenSheetDismiss == nil {
                    CardPreviewModeBackground().ignoresSafeArea()
                }

                FlipCard(
                    frontZone: front.rootZone,
                    backZone: back.rootZone,
                    isFlipped: $isFlipped
                )
                .frame(maxWidth: .infinity)
                .frame(height: availableCardHeight)
                .layoutPriority(1)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.interactiveSpring(response: 0.45, dampingFraction: 0.85)) {
                        isFlipped.toggle()
                    }
                }
                .padding(.top, cardTopInset)
                .padding(.horizontal, cardHorizontalInset)
                .padding(.bottom, cardBottomPadding)

                topChrome(safeTopInset: resolvedSafeTopInset, horizontalInset: headerHorizontalInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .fullScreenSheetDragActivationHeight(cardTopInset)
        }
    }

    private func topChrome(safeTopInset: CGFloat, horizontalInset: CGFloat) -> some View {
        VStack(spacing: UIConstants.Spacing.small) {
            Capsule()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.2 : 0.35))
                .frame(width: 56, height: 5)
                .accessibilityHidden(true)

            ZStack {
                VStack(spacing: 2) {
                    Text("Preview Mode")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    faceLabel
                }
                HStack {
                    Color.clear.frame(width: sideControlWidth, height: 1)
                    Spacer(minLength: 0)
                    doneButton.frame(width: sideControlWidth, alignment: .trailing)
                }
            }
            .frame(height: chromeButtonHeight)
        }
        .padding(.top, safeTopInset + UIConstants.Spacing.tiny)
        .padding(.horizontal, horizontalInset)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { newH in
            if abs(topChromeHeight - newH) > 0.5 { topChromeHeight = newH }
        }
    }

    private var faceLabel: some View {
        Text(isFlipped ? "ANSWER" : "QUESTION")
            .font(.system(size: UIConstants.Size.navigationChromeLabel, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var doneButton: some View {
        Button(action: handleDone) {
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: chromeButtonHeight, height: chromeButtonHeight)
                .glassButton(shape: .circle)
        }
        .buttonStyle(.plain)
    }

    private func handleDone() {
        if let fullScreenSheetDismiss { fullScreenSheetDismiss() } else { dismiss() }
    }
}

// MARK: - Card Preview Mode Background

/// At rest: pure black (dark) / systemGray6 (light).
///
/// During drag a very dark charcoal gradient appears **only at the top** of the
/// surface, fading to transparent at ~25 % of height.  This makes the rounded
/// top corners clearly visible against the dark strip while the body stays black.
///
/// The overlay reaches full opacity at just 10 % of screen travel so the effect
/// is visible within the very first pixels of a drag.
struct CardPreviewModeBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.fullScreenSheetDragProgress) private var dragProgress

    /// Reaches 1.0 after only 10 % of screen travel.
    private var overlayOpacity: Double {
        min(dragProgress / 0.10, 1.0)
    }

    var body: some View {
        ZStack {
            // ── Base ────────────────────────────────────────────────────────
            if colorScheme == .dark {
                Color.black
            } else {
                Color(uiColor: .systemGray6)
            }

            // ── Top-strip dark charcoal gradient ────────────────────────────
            LinearGradient(
                stops: [
                    .init(color: Color(white: colorScheme == .dark ? 0.08 : 0.70), location: 0.00),
                    .init(color: Color(white: colorScheme == .dark ? 0.08 : 0.70), location: 0.04),
                    .init(color: .clear,                                             location: 0.25)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(overlayOpacity)
        }
    }
}
