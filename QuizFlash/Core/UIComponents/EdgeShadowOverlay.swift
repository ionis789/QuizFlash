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

/// Maximum opacity at the solid edge of the gradient.
/// 1.0 = fully opaque at the screen edge. Lower = subtler vignette overall.
private let kMaxAlpha: CGFloat = 0.6
//private let kMaxAlpha: CGFloat = 0.88

// MARK: - EdgeShadowOverlay

struct EdgeShadowOverlay: View {

    /// Height of the top gradient (safeTop + header content height).
    /// Pass 0 to hide the top shadow.
    var topHeight: CGFloat = 0

    /// Height of the bottom gradient (should cover tab bar + home indicator).
    /// Pass 0 to hide the bottom shadow.
    var bottomHeight: CGFloat = 0

    var body: some View {
        ZStack {
            if topHeight > 0 {
                VStack(spacing: 0) {
                    _CAGradientView(direction: .top, height: topHeight)
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
                    _CAGradientView(direction: .bottom, height: bottomHeight)
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

/// Core Animation gradient view. Rendered by GPU in linear color space —
/// no banding (unlike SwiftUI LinearGradient on OLED) and no shimmer
/// (unlike UIVisualEffectView). Same black hue at every stop, only alpha
/// changes, eliminating the sRGB hue-shift that causes visible banding.
private struct _CAGradientView: UIViewRepresentable {

    let direction: _GradientDirection
    let height: CGFloat

    func makeUIView(context: Context) -> _LayerView {
        _LayerView(direction: direction)
    }

    func updateUIView(_ uiView: _LayerView, context: Context) {
        uiView.updateHeight(height)
    }

    // MARK: _LayerView

    final class _LayerView: UIView {

        private let gradientLayer = CAGradientLayer()

        init(direction: _GradientDirection) {
            super.init(frame: .zero)
            backgroundColor = .clear
            isUserInteractionEnabled = false

            // ── Spread factor ──────────────────────────────────────────────────
            // Normalises kShadowRadius (range 60–180) into a 0–1 curve offset.
            // At radius 60  → spreadFactor ≈ 0.0 → stops pushed to the edge
            //                  (tight, defined shadow).
            // At radius 120 → spreadFactor ≈ 0.5 → balanced curve (original feel).
            // At radius 180 → spreadFactor ≈ 1.0 → stops pulled toward center
            //                  (wide, misty fade).
            let normalised = (kShadowRadius - 60) / 120            // 0…1
            let spread = max(0, min(1, normalised))                 // clamp

            // Base location anchors (tight). Spread shifts them toward center,
            // making the transition zone wider relative to the gradient height.
            // The first and last stops stay fixed (0.0 / 1.0) — only the
            // intermediate stops move, which controls the curve shape.
            let l1 = 0.08 + spread * 0.10   // was 0.08 → up to 0.18
            let l2 = 0.22 + spread * 0.16   // was 0.22 → up to 0.38
            let l3 = 0.48 + spread * 0.18   // was 0.48 → up to 0.66
            let l4 = 0.75 + spread * 0.12   // was 0.75 → up to 0.87

            let locations: [NSNumber] = [0.0, l1, l2, l3, l4, 1.0].map { NSNumber(value: $0) }

            // Alpha curve: front-loaded near the solid edge; tapering toward transparent.
            // kMaxAlpha caps overall intensity so vignette can be softened globally.
            let alphas: [CGFloat]
            switch direction {
            case .top:
                // solid → clear  (top of screen → content)
                alphas = [kMaxAlpha, kMaxAlpha * 0.90, kMaxAlpha * 0.65, kMaxAlpha * 0.25, kMaxAlpha * 0.05, 0.0]
            case .bottom:
                // clear → solid  (content → bottom of screen)
                alphas = [0.0, kMaxAlpha * 0.05, kMaxAlpha * 0.25, kMaxAlpha * 0.65, kMaxAlpha * 0.90, kMaxAlpha]
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
            gradientLayer.frame = CGRect(
                x: 0, y: 0,
                width: UIScreen.main.bounds.width,
                height: height
            )
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
