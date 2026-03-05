//
//  EdgeShadowOverlay.swift
//  QuizFlash
//
//  Reusable top + bottom CAGradientLayer vignette.
//
//  USAGE — any screen with a floating header/tabbar:
//
//      ZStack {
//          YourScrollContent()
//          EdgeShadowOverlay(topHeight: headerHeight + safeTop)
//      }
//
//  TUNING:
//      kShadowRadius  →  controls how soft/spread the gradient fade is.
//                        LOWER value = tighter, more defined shadow (stops transition early).
//                        HIGHER value = softer, wider fade — "mist" effect.
//                        Recommended range: 60–180pt.
//
//  BUG FIX (v2):
//      Previously kShadowRadius was declared but never used — all alpha stops
//      and location offsets were hardcoded, making the constant a no-op.
//      Now `kShadowRadius` drives `spreadFactor`, which parametrically shifts
//      the gradient location stops:
//        • Low radius  → stops compressed toward the edge (defined vignette).
//        • High radius → stops spread outward (feathered mist fade).
//      Max alpha is also capped at `kMaxAlpha` so the shadow intensity
//      can be tuned independently from the spread.

import SwiftUI

// MARK: - Tuning Constants

/// Controls the softness/spread of the gradient fade on both edges.
/// Range: 60–180. Higher = more misty/feathered.
private let kShadowRadius: CGFloat = 160

// MARK: - EdgeShadowOverlay

struct EdgeShadowOverlay: View {

    /// Height of the top gradient (safeTop + header content height). Pass 0 to hide.
    var topHeight: CGFloat = 0
    /// Height of the bottom gradient (tab bar + home indicator). Pass 0 to hide.
    var bottomHeight: CGFloat = 0

    // ─── Control these two values to tune each shadow independently ───────
    /// Intensity of the TOP shadow.    0.0 = invisible  →  1.0 = fully black
    var kMaxAlphaTop: CGFloat = 0.8
    /// Intensity of the BOTTOM shadow. 0.0 = invisible  →  1.0 = fully black
    var kMaxAlphaBottom: CGFloat = 0.4
    // ──────────────────────────────────────────────────────────────────────

    var body: some View {
        ZStack {
            if topHeight > 0 {
                VStack(spacing: 0) {
                    _CAGradientView(
                        direction: .top,
                        height: topHeight,
                        maxAlpha: kMaxAlphaTop           // ← top intensity
                    )
                    .frame(height: topHeight)
                    .ignoresSafeArea(.all, edges: .top)
                    .allowsHitTesting(false)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }

            if bottomHeight > 0 {
                VStack(spacing: 0) {
                    Spacer()
                    _CAGradientView(
                        direction: .bottom,
                        height: bottomHeight,
                        maxAlpha: kMaxAlphaBottom        // ← bottom intensity
                    )
                    .frame(height: bottomHeight)
                    .ignoresSafeArea(.all, edges: .bottom)
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.all, edges: .bottom)
                .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Direction

private enum _GradientDirection { case top, bottom }

// MARK: - _CAGradientView

/// Core Animation gradient view. GPU-rendered in linear color space —
/// no banding and no shimmer. Only alpha changes at every stop.
private struct _CAGradientView: UIViewRepresentable {

    let direction: _GradientDirection
    let height: CGFloat
    /// Maximum opacity at the solid edge. Passed from EdgeShadowOverlay separately
    /// for top and bottom so each can be tuned independently.
    let maxAlpha: CGFloat

    func makeUIView(context: Context) -> _LayerView {
        _LayerView(direction: direction, maxAlpha: maxAlpha)
    }

    func updateUIView(_ uiView: _LayerView, context: Context) {
        uiView.updateHeight(height)
    }

    // MARK: _LayerView

    final class _LayerView: UIView {

        private let gradientLayer = CAGradientLayer()

        init(direction: _GradientDirection, maxAlpha: CGFloat) {
            super.init(frame: .zero)
            backgroundColor = .clear
            isUserInteractionEnabled = false

            // ── Spread factor ──────────────────────────────────────────────
            // Normalises kShadowRadius (60–180) into a 0–1 curve offset.
            // Low  → tight, defined vignette.
            // High → wide, misty fade.
            let normalised = (kShadowRadius - 60) / 120
            let spread = max(0, min(1, normalised))

            let l1 = 0.08 + spread * 0.10
            let l2 = 0.22 + spread * 0.16
            let l3 = 0.48 + spread * 0.18
            let l4 = 0.75 + spread * 0.12

            let locations: [NSNumber] = [0.0, l1, l2, l3, l4, 1.0].map { NSNumber(value: $0) }

            // Alpha curve — uses the single `maxAlpha` passed in for this edge.
            // The multipliers shape the curve (front-loaded near the solid edge).
            let alphas: [CGFloat]
            switch direction {
            case .top:
                // solid → clear  (top of screen → content)
                alphas = [maxAlpha,
                          maxAlpha * 0.90,
                          maxAlpha * 0.65,
                          maxAlpha * 0.25,
                          maxAlpha * 0.05,
                          0.0]
            case .bottom:
                // clear → solid  (content → bottom of screen)
                alphas = [0.0,
                          maxAlpha * 0.05,
                          maxAlpha * 0.25,
                          maxAlpha * 0.65,
                          maxAlpha * 0.90,
                          maxAlpha]
            }

            gradientLayer.colors    = alphas.map { UIColor.black.withAlphaComponent($0).cgColor }
            gradientLayer.locations = locations
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
            gradientLayer.endPoint   = CGPoint(x: 0.5, y: 1)
            layer.addSublayer(gradientLayer)
        }

        required init?(coder: NSCoder) { fatalError() }

        func updateHeight(_ height: CGFloat) {
            guard height > 0 else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            gradientLayer.frame = CGRect(x: 0, y: 0,
                                         width: UIScreen.main.bounds.width,
                                         height: height)
            CATransaction.commit()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard gradientLayer.frame.height > 0 else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            gradientLayer.frame.size.width = bounds.width
            CATransaction.commit()
        }
    }
}
