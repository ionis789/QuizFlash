//
//  View+ScreenTopEdgeShadow.swift
//  QuizFlash
//
//  Shared top-edge shadow treatment for screen-root background/content layers.
//

import SwiftUI

enum ScreenTopEdgeStyle {
    case shadow
    case progressiveBlur(ScreenTopProgressiveBlurConfiguration = .quizFlashDefault)
}

private struct ScreenTopEdgeShadowModifier: ViewModifier {
    @Environment(DevelopmentPreferences.self) private var developmentPreferences

    let topHeight: CGFloat
    let bottomHeight: CGFloat
    let topRevealProgress: CGFloat
    let bottomRevealProgress: CGFloat
    let fullScreenFillProgress: CGFloat
    let fullScreenDimOpacity: CGFloat
    let fullScreenBlurRadius: CGFloat
    let debugScreenID: String?
    let style: ScreenTopEdgeStyle

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack(alignment: .bottomTrailing) {
                    fullScreenProgressiveBlurOverlay
                    edgeOverlays

                    if shouldRenderLegacyFullScreenFill {
                        EdgeShadowOverlay(
                            topHeight: 0,
                            bottomHeight: 0,
                            topRevealProgress: 1,
                            fullScreenFillProgress: fullScreenFillProgress,
                            fullScreenDimOpacity: fullScreenDimOpacity,
                            fullScreenFillColor: resolvedTopColor
                        )
                    }

#if DEBUG
                    if let debugScreenID, developmentPreferences.edgeShadowTuningEnabled {
                        EdgeShadowDebugFloatingPanel(
                            mode: debugPanelMode,
                            supportsBottomEdge: false,
                            settings: debugSettingsBinding(for: debugScreenID),
                            onReset: {
                                developmentPreferences.resetEdgeShadowSettings(for: debugScreenID)
                            }
                        )
                        .padding(.trailing, UIConstants.Spacing.medium)
                        .padding(.bottom, 92)
                        .zIndex(1)
                    }
#endif
                }
            }
    }

    private var resolvedDebugSettings: EdgeShadowDebugSettings {
        guard let debugScreenID else { return .default }
        return developmentPreferences.edgeShadowSettings(for: debugScreenID)
    }

    private var resolvedTopHeight: CGFloat {
        guard debugScreenID != nil else { return max(0, topHeight) }
        return resolvedDebugSettings.resolvedTopHeight(from: topHeight)
    }

    private var resolvedBottomHeight: CGFloat {
        guard debugScreenID != nil else { return max(0, bottomHeight) }
        return resolvedDebugSettings.resolvedBottomHeight(from: bottomHeight)
    }

    private var resolvedMaxAlpha: CGFloat {
        guard debugScreenID != nil else { return 1.0 }
        return resolvedDebugSettings.maxAlpha
    }

    private var resolvedBottomMaxAlpha: CGFloat {
        guard debugScreenID != nil else { return 1.0 }
        return resolvedDebugSettings.bottomMaxAlpha
    }

    private var resolvedTuning: EdgeShadowTuning {
        guard debugScreenID != nil else { return .default }
        return resolvedDebugSettings.tuning
    }

    private var resolvedTopColor: Color {
        guard debugScreenID != nil else { return EdgeShadowDebugSettings.default.resolvedColor }
        return resolvedDebugSettings.resolvedColor
    }

    private var resolvedBottomColor: Color {
        guard debugScreenID != nil else { return EdgeShadowDebugSettings.default.resolvedColor }
        return resolvedDebugSettings.resolvedBottomColor
    }

    private var resolvedTopRevealProgress: CGFloat {
        guard debugScreenID != nil else { return min(max(topRevealProgress, 0), 1) }
        guard resolvedDebugSettings.topEnabled else { return 0 }
        return min(max(topRevealProgress, 0), 1)
    }

    private var resolvedBottomRevealProgress: CGFloat {
        guard debugScreenID != nil else { return min(max(bottomRevealProgress, 0), 1) }
        guard resolvedDebugSettings.bottomEnabled else { return 0 }
        return min(max(bottomRevealProgress, 0), 1)
    }

    private var clampedFullScreenFillProgress: CGFloat {
        min(max(fullScreenFillProgress, 0), 1)
    }

    private var resolvedFullScreenBlurRadius: CGFloat {
        max(0, fullScreenBlurRadius)
    }

    private var shouldRenderLegacyFullScreenFill: Bool {
        guard case .shadow = style else { return false }
        return fullScreenFillProgress > 0.001 || fullScreenDimOpacity > 0.001
    }

    @ViewBuilder
    private var edgeOverlays: some View {
        switch style {
        case .shadow:
            EdgeShadowOverlay(
                topHeight: resolvedTopHeight,
                bottomHeight: resolvedBottomHeight,
                kMaxAlphaTop: resolvedMaxAlpha,
                kMaxAlphaBottom: resolvedBottomMaxAlpha,
                topColor: resolvedTopColor,
                bottomColor: resolvedBottomColor,
                topProfileHeight: max(0, topHeight),
                bottomProfileHeight: max(0, bottomHeight),
                tuning: resolvedTuning,
                topRevealProgress: resolvedTopRevealProgress,
                bottomRevealProgress: resolvedBottomRevealProgress
            )
        case .progressiveBlur(let configuration):
            ScreenEdgeProgressiveBlurOverlay(
                edge: .top,
                height: resolvedTopHeight,
                revealProgress: resolvedTopRevealProgress,
                tintColor: resolvedTopColor,
                configuration: resolvedProgressiveBlurConfiguration(fallback: configuration)
            )
            ScreenEdgeProgressiveBlurOverlay(
                edge: .bottom,
                height: resolvedBottomHeight,
                revealProgress: resolvedBottomRevealProgress,
                tintColor: resolvedBottomColor,
                configuration: resolvedBottomProgressiveBlurConfiguration(fallback: configuration)
            )
        }
    }

    @ViewBuilder
    private var fullScreenProgressiveBlurOverlay: some View {
        if case .progressiveBlur = style,
           clampedFullScreenFillProgress > 0.001,
           resolvedFullScreenBlurRadius > 0.001 {
            ZStack {
                BackgroundBlurView(radius: resolvedFullScreenBlurRadius)
                    .ignoresSafeArea()

                resolvedTopColor
                    .opacity(fullScreenDimOpacity)
                    .ignoresSafeArea()
            }
            .opacity(clampedFullScreenFillProgress)
            .animation(.easeInOut(duration: 0.18), value: clampedFullScreenFillProgress)
            .allowsHitTesting(false)
        }
    }

    private func resolvedProgressiveBlurConfiguration(
        fallback: ScreenTopProgressiveBlurConfiguration
    ) -> ScreenTopProgressiveBlurConfiguration {
        guard debugScreenID != nil else { return fallback }
        return resolvedDebugSettings.progressiveBlurConfiguration
    }

    private func resolvedBottomProgressiveBlurConfiguration(
        fallback: ScreenTopProgressiveBlurConfiguration
    ) -> ScreenTopProgressiveBlurConfiguration {
        guard debugScreenID != nil else { return fallback }
        return resolvedDebugSettings.bottomProgressiveBlurConfiguration
    }

#if DEBUG
    private var debugPanelMode: TopChromeDebugPanelMode {
        switch style {
        case .shadow:
            return .shadow
        case .progressiveBlur:
            return .progressiveBlur
        }
    }

    private func debugSettingsBinding(for screenID: String) -> Binding<EdgeShadowDebugSettings> {
        Binding(
            get: { developmentPreferences.edgeShadowSettings(for: screenID) },
            set: { developmentPreferences.setEdgeShadowSettings($0, for: screenID) }
        )
    }
#endif
}

extension View {
    /// Applies the shared screen-level top-edge shadow.
    ///
    /// Apply this at the root background/content layer before `.safeAreaInset(edge: .top)`
    /// or top-chrome overlays so the chrome remains visually above the fade.
    func screenTopEdgeShadow(
        topHeight: CGFloat,
        topRevealProgress: CGFloat = 1,
        debugScreenID: String? = nil,
        fullScreenFillProgress: CGFloat = 0,
        fullScreenDimOpacity: CGFloat = 0,
        fullScreenBlurRadius: CGFloat = 0,
        style: ScreenTopEdgeStyle = .shadow
    ) -> some View {
        modifier(
            ScreenTopEdgeShadowModifier(
                topHeight: topHeight,
                bottomHeight: 0,
                topRevealProgress: topRevealProgress,
                bottomRevealProgress: 1,
                fullScreenFillProgress: fullScreenFillProgress,
                fullScreenDimOpacity: fullScreenDimOpacity,
                fullScreenBlurRadius: fullScreenBlurRadius,
                debugScreenID: debugScreenID,
                style: style
            )
        )
    }

    /// Applies shared screen-level top and bottom edge blur/shadow treatments.
    func screenEdgeShadow(
        topHeight: CGFloat = 0,
        bottomHeight: CGFloat = 0,
        topRevealProgress: CGFloat = 1,
        bottomRevealProgress: CGFloat = 1,
        debugScreenID: String? = nil,
        fullScreenFillProgress: CGFloat = 0,
        fullScreenDimOpacity: CGFloat = 0,
        fullScreenBlurRadius: CGFloat = 0,
        style: ScreenTopEdgeStyle = .shadow
    ) -> some View {
        modifier(
            ScreenTopEdgeShadowModifier(
                topHeight: topHeight,
                bottomHeight: bottomHeight,
                topRevealProgress: topRevealProgress,
                bottomRevealProgress: bottomRevealProgress,
                fullScreenFillProgress: fullScreenFillProgress,
                fullScreenDimOpacity: fullScreenDimOpacity,
                fullScreenBlurRadius: fullScreenBlurRadius,
                debugScreenID: debugScreenID,
                style: style
            )
        )
    }
}
