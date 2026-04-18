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
    let topRevealProgress: CGFloat
    let fullScreenFillProgress: CGFloat
    let fullScreenDimOpacity: CGFloat
    let debugScreenID: String?
    let style: ScreenTopEdgeStyle

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack(alignment: .bottomTrailing) {
                    topEdgeOverlay

                    if fullScreenFillProgress > 0.001 || fullScreenDimOpacity > 0.001 {
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

    private var resolvedMaxAlpha: CGFloat {
        guard debugScreenID != nil else { return 1.0 }
        return resolvedDebugSettings.maxAlpha
    }

    private var resolvedTuning: EdgeShadowTuning {
        guard debugScreenID != nil else { return .default }
        return resolvedDebugSettings.tuning
    }

    private var resolvedTopColor: Color {
        guard debugScreenID != nil else { return EdgeShadowDebugSettings.default.resolvedColor }
        return resolvedDebugSettings.resolvedColor
    }

    @ViewBuilder
    private var topEdgeOverlay: some View {
        switch style {
        case .shadow:
            EdgeShadowOverlay(
                topHeight: resolvedTopHeight,
                bottomHeight: 0,
                kMaxAlphaTop: resolvedMaxAlpha,
                topColor: resolvedTopColor,
                topProfileHeight: max(0, topHeight),
                tuning: resolvedTuning,
                topRevealProgress: topRevealProgress
            )
        case .progressiveBlur(let configuration):
            TopProgressiveBlurOverlay(
                topHeight: resolvedTopHeight,
                revealProgress: topRevealProgress,
                tintColor: resolvedTopColor,
                configuration: resolvedProgressiveBlurConfiguration(fallback: configuration)
            )
        }
    }

    private func resolvedProgressiveBlurConfiguration(
        fallback: ScreenTopProgressiveBlurConfiguration
    ) -> ScreenTopProgressiveBlurConfiguration {
        guard debugScreenID != nil else { return fallback }
        return resolvedDebugSettings.progressiveBlurConfiguration
    }

    private var debugPanelMode: TopChromeDebugPanelMode {
        switch style {
        case .shadow:
            return .shadow
        case .progressiveBlur:
            return .progressiveBlur
        }
    }

#if DEBUG
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
        style: ScreenTopEdgeStyle = .shadow
    ) -> some View {
        modifier(
            ScreenTopEdgeShadowModifier(
                topHeight: topHeight,
                topRevealProgress: topRevealProgress,
                fullScreenFillProgress: fullScreenFillProgress,
                fullScreenDimOpacity: fullScreenDimOpacity,
                debugScreenID: debugScreenID,
                style: style
            )
        )
    }
}
