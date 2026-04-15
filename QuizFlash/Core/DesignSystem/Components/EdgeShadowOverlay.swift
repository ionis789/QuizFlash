//
//  EdgeShadowOverlay.swift
//  QuizFlash
//
//  Reusable top + bottom CAGradientLayer vignette.
//
//  USAGE — any screen with a floating header/tab bar:
//
//      ZStack {
//          YourScrollContent()
//          EdgeShadowOverlay(topHeight: headerHeight + safeTop)
//      }
//
//  TUNING:
//      kShadowRadius  →  caps the feather band used by the adaptive fade.
//                        LOWER value = tighter, shorter edge blur.
//                        HIGHER value = softer, longer edge blur.
//                        Recommended range: 60–180 pt.
//
//  ADAPTIVE PROFILE:
//      The overlay uses a dense hold zone plus a soft feather band.
//      Most of the height stays visually uniform, while only the trailing edge
//      fades out, which better matches iOS floating chrome treatments.

import SwiftUI
import UIKit

// MARK: - Tuning Constants

/// Controls the maximum feather-band length used by the adaptive fade.
/// Range: 60–180. Higher = softer and more extended.
private let kShadowRadius: CGFloat = 160
private let kDefaultEdgeShadowColor = Color(ThemeColorToken.backgroundPrimary.assetName)

// MARK: - EdgeShadowOverlay

struct EdgeShadowTuning: Equatable {
    /// Scales only the feather band at the trailing edge, not the full shadow zone.
    var fadeLengthScale: CGFloat = 1.35

    /// Adaptive lower/upper bounds for feather coverage across different heights.
    var minimumFadeCoverage: CGFloat = 0.24
    var maximumFadeCoverage: CGFloat = 0.40

    /// Controls how quickly the feather band falls off near its end.
    var curveExponentBase: CGFloat = 0.70
    var curveExponentHeightScale: CGFloat = 0.12
    var blurOpacityScale: CGFloat = 0.66
    var tintOpacityScale: CGFloat = 0.72

    static let `default` = EdgeShadowTuning()
}

struct EdgeShadowDebugSettings: Codable, Equatable {
    var maxAlpha: CGFloat = 1.0
    var blurOpacityScale: CGFloat = EdgeShadowTuning.default.blurOpacityScale
    var tintOpacityScale: CGFloat = EdgeShadowTuning.default.tintOpacityScale
    var fadeLengthScale: CGFloat = EdgeShadowTuning.default.fadeLengthScale
    var curveExponentBase: CGFloat = EdgeShadowTuning.default.curveExponentBase
    var heightOffset: CGFloat = 0
    var colorOverride: EdgeShadowDebugColor?

    static let `default` = EdgeShadowDebugSettings()

    var tuning: EdgeShadowTuning {
        var tuning = EdgeShadowTuning.default
        tuning.blurOpacityScale = blurOpacityScale
        tuning.tintOpacityScale = tintOpacityScale
        tuning.fadeLengthScale = fadeLengthScale
        tuning.curveExponentBase = curveExponentBase
        return tuning
    }

    func resolvedTopHeight(from baseHeight: CGFloat) -> CGFloat {
        max(0, baseHeight + heightOffset)
    }

    var resolvedColor: Color {
        colorOverride?.swiftUIColor ?? kDefaultEdgeShadowColor
    }
}

struct EdgeShadowDebugColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(color: Color) {
        let resolved = UIColor(color)
        var redComponent: CGFloat = 0
        var greenComponent: CGFloat = 0
        var blueComponent: CGFloat = 0
        var alphaComponent: CGFloat = 0

        if resolved.getRed(&redComponent, green: &greenComponent, blue: &blueComponent, alpha: &alphaComponent) {
            self.red = redComponent
            self.green = greenComponent
            self.blue = blueComponent
        } else {
            self.red = 0
            self.green = 0
            self.blue = 0
        }
    }

    var swiftUIColor: Color {
        Color(
            red: red,
            green: green,
            blue: blue
        )
    }
}

/// A non-interactive overlay that applies a smooth gradient vignette at
/// the top and/or bottom edges of the screen, masking floating headers and
/// tab bars into the scroll content below.
///
/// Place inside a `ZStack` on top of your scroll content:
/// ```swift
/// ZStack {
///     MyScrollView()
///     EdgeShadowOverlay(topHeight: headerHeight + safeTop,
///                       bottomHeight: tabBarHeight)
/// }
/// ```
struct EdgeShadowOverlay: View {

    // MARK: - Configuration

    /// Height of the top gradient (safe area inset + header content height). Pass `0` to hide.
    var topHeight: CGFloat = 0

    /// Height of the bottom gradient (tab bar + home indicator). Pass `0` to hide.
    var bottomHeight: CGFloat = 0

    /// Intensity of the top shadow. `0.0` = invisible, `1.0` = fully opaque black.
    var kMaxAlphaTop: CGFloat = 1.0

    /// Intensity of the bottom shadow. `0.0` = invisible, `1.0` = fully opaque black.
    var kMaxAlphaBottom: CGFloat = 0.5

    /// Tint color used by the top shadow gradient.
    var topColor: Color = kDefaultEdgeShadowColor

    /// Tint color used by the bottom shadow gradient.
    var bottomColor: Color = kDefaultEdgeShadowColor

    /// Reference height used only for shaping the top fade profile.
    /// This lets the visible area grow without changing the internal tone curve.
    var topProfileHeight: CGFloat? = nil

    /// Reference height used only for shaping the bottom fade profile.
    var bottomProfileHeight: CGFloat? = nil

    /// Advanced tuning knobs for fade shape and perceived blur density.
    var tuning: EdgeShadowTuning = .default

    /// Opacity progress used to fade the top shadow in/out with compact-title chrome.
    var topRevealProgress: CGFloat = 1

    /// Extra fullscreen dim layer that grows downward from the top edge.
    /// Keeps the top vignette visually dominant while softly defocusing the
    /// rest of the screen during transient states such as frozen search browse.
    var fullScreenFillProgress: CGFloat = 0

    /// Opacity applied to the fullscreen dim layer once it has expanded.
    var fullScreenDimOpacity: CGFloat = 0

    /// Optional override used by the fullscreen fill layer.
    var fullScreenFillColor: Color? = nil

    private var clampedFullScreenFillProgress: CGFloat {
        min(max(fullScreenFillProgress, 0), 1)
    }

    private var resolvedFullScreenFillColor: Color {
        fullScreenFillColor ?? topColor
    }

    private var clampedTopRevealProgress: CGFloat {
        min(max(topRevealProgress, 0), 1)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(resolvedFullScreenFillColor.opacity(fullScreenDimOpacity))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(
                        x: 1,
                        y: max(clampedFullScreenFillProgress, 0.001),
                        anchor: .top
                    )
                    .opacity(clampedFullScreenFillProgress > 0.001 ? 1 : 0)
                    .ignoresSafeArea(.all)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .allowsHitTesting(false)

                if topHeight > 0 {
                    VStack(spacing: 0) {
                        _CAGradientView(
                            direction: .top,
                            height: topHeight,
                            profileHeight: topProfileHeight ?? topHeight,
                            maxAlpha: kMaxAlphaTop,
                            baseColor: UIColor(topColor),
                            tuning: tuning
                        )
                        .frame(height: topHeight)
                        .opacity(clampedTopRevealProgress)
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
                            profileHeight: bottomProfileHeight ?? bottomHeight,
                            maxAlpha: kMaxAlphaBottom,
                            baseColor: UIColor(bottomColor),
                            tuning: tuning
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
            .animation(CollapsibleTitleChromeMetrics.shadowFadeAnimation, value: clampedTopRevealProgress)
            .animation(.easeInOut(duration: 0.22), value: clampedFullScreenFillProgress)
            .animation(.easeInOut(duration: 0.22), value: fullScreenDimOpacity)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Direction

private enum _GradientDirection { case top, bottom }

private struct _AdaptiveGradientProfile {
    let locations: [NSNumber]
    let alphaFactors: [CGFloat]

    static func make(
        totalHeight: CGFloat,
        profileHeight: CGFloat,
        direction: _GradientDirection,
        tuning: EdgeShadowTuning
    ) -> _AdaptiveGradientProfile {
        let clampedTotalHeight = max(totalHeight, 1)
        let clampedProfileHeight = max(min(profileHeight, clampedTotalHeight), 1)
        let normalizedHeight = min(max(clampedProfileHeight / kShadowRadius, 0), 1)
        let baseFeatherCoverage = tuning.maximumFadeCoverage
            + ((tuning.minimumFadeCoverage - tuning.maximumFadeCoverage) * normalizedHeight)
        let featherHeight = min(
            max(clampedProfileHeight * baseFeatherCoverage * tuning.fadeLengthScale, 8),
            clampedTotalHeight * 0.92
        )
        let holdCoverage = max(0, (clampedTotalHeight - featherHeight) / clampedTotalHeight)
        let featherCoverage = max(1 - holdCoverage, 0.08)
        let curveExponent = tuning.curveExponentBase + (normalizedHeight * tuning.curveExponentHeightScale)
        let localSamples: [CGFloat] = [0, 0.02, 0.05, 0.09, 0.14, 0.20, 0.28, 0.38, 0.50, 0.64, 0.78, 0.89, 0.96, 1]

        var stops: [(location: CGFloat, alphaFactor: CGFloat)] = [(0, 1)]

        if holdCoverage > 0.001 {
            stops.append((holdCoverage, 1))
        }

        stops.append(
            contentsOf: localSamples.map { sample in
                let featherProgress = _smootherStep(sample)
                let alphaFactor = pow(1 - featherProgress, curveExponent)
                return (
                    location: min(holdCoverage + (sample * featherCoverage), 1),
                    alphaFactor: alphaFactor
                )
            }
        )

        switch direction {
        case .top:
            return _AdaptiveGradientProfile(
                locations: stops.map { NSNumber(value: Double($0.location)) },
                alphaFactors: stops.map(\.alphaFactor)
            )
        case .bottom:
            let mirroredStops = stops
                .map { (location: 1 - $0.location, alphaFactor: $0.alphaFactor) }
                .reversed()
            return _AdaptiveGradientProfile(
                locations: mirroredStops.map { NSNumber(value: Double($0.location)) },
                alphaFactors: mirroredStops.map(\.alphaFactor)
            )
        }
    }
}

private func _smootherStep(_ value: CGFloat) -> CGFloat {
    let x = min(max(value, 0), 1)
    return x * x * x * (x * ((x * 6) - 15) + 10)
}

// MARK: - _CAGradientView

/// Core Animation gradient view. GPU-rendered in linear colour space —
/// no banding and no shimmer. Only alpha changes at every stop.
private struct _CAGradientView: UIViewRepresentable {

    // MARK: - Properties

    let direction: _GradientDirection
    let height: CGFloat
    let profileHeight: CGFloat

    /// Maximum opacity at the solid edge. Passed separately for each edge
    /// so top and bottom intensities can be tuned independently.
    let maxAlpha: CGFloat

    /// Base tint used for the rendered edge fade.
    let baseColor: UIColor

    /// Adaptive tuning for fade curve and blur/tint density.
    let tuning: EdgeShadowTuning

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> _LayerView {
        _LayerView(
            direction: direction,
            maxAlpha: maxAlpha,
            baseColor: baseColor,
            tuning: tuning,
            profileHeight: profileHeight
        )
    }

    func updateUIView(_ uiView: _LayerView, context: Context) {
        uiView.update(
            height: height,
            profileHeight: profileHeight,
            maxAlpha: maxAlpha,
            baseColor: baseColor,
            tuning: tuning
        )
    }

    // MARK: - _LayerView

    /// The backing `UIView` that hosts the `CAGradientLayer`.
    final class _LayerView: UIView {

        private let blurView = _TransparentBackdropBlurView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        private let boostBlurView = _TransparentBackdropBlurView(effect: UIBlurEffect(style: .systemThinMaterial))
        private let maxBoostBlurView = _TransparentBackdropBlurView(effect: UIBlurEffect(style: .systemMaterial))
        private let extremeBlurView = _TransparentBackdropBlurView(effect: UIBlurEffect(style: .systemThickMaterial))
        private let ultraBlurView = _TransparentBackdropBlurView(effect: UIBlurEffect(style: .prominent))
        private let hyperBlurView = _TransparentBackdropBlurView(effect: UIBlurEffect(style: .prominent))
        private let blurMaskLayer = CAGradientLayer()
        private let boostBlurMaskLayer = CAGradientLayer()
        private let maxBoostBlurMaskLayer = CAGradientLayer()
        private let extremeBlurMaskLayer = CAGradientLayer()
        private let ultraBlurMaskLayer = CAGradientLayer()
        private let hyperBlurMaskLayer = CAGradientLayer()
        private let gradientLayer = CAGradientLayer()
        private let direction: _GradientDirection

        init(
            direction: _GradientDirection,
            maxAlpha: CGFloat,
            baseColor: UIColor,
            tuning: EdgeShadowTuning,
            profileHeight: CGFloat
        ) {
            self.direction = direction
            super.init(frame: .zero)
            backgroundColor = .clear
            isUserInteractionEnabled = false

            blurView.isUserInteractionEnabled = false
            boostBlurView.isUserInteractionEnabled = false
            maxBoostBlurView.isUserInteractionEnabled = false
            extremeBlurView.isUserInteractionEnabled = false
            ultraBlurView.isUserInteractionEnabled = false
            hyperBlurView.isUserInteractionEnabled = false
            addSubview(blurView)
            addSubview(boostBlurView)
            addSubview(maxBoostBlurView)
            addSubview(extremeBlurView)
            addSubview(ultraBlurView)
            addSubview(hyperBlurView)
            blurView.layer.mask = blurMaskLayer
            boostBlurView.layer.mask = boostBlurMaskLayer
            maxBoostBlurView.layer.mask = maxBoostBlurMaskLayer
            extremeBlurView.layer.mask = extremeBlurMaskLayer
            ultraBlurView.layer.mask = ultraBlurMaskLayer
            hyperBlurView.layer.mask = hyperBlurMaskLayer

            blurMaskLayer.startPoint = CGPoint(x: 0.5, y: 0)
            blurMaskLayer.endPoint = CGPoint(x: 0.5, y: 1)
            boostBlurMaskLayer.startPoint = CGPoint(x: 0.5, y: 0)
            boostBlurMaskLayer.endPoint = CGPoint(x: 0.5, y: 1)
            maxBoostBlurMaskLayer.startPoint = CGPoint(x: 0.5, y: 0)
            maxBoostBlurMaskLayer.endPoint = CGPoint(x: 0.5, y: 1)
            extremeBlurMaskLayer.startPoint = CGPoint(x: 0.5, y: 0)
            extremeBlurMaskLayer.endPoint = CGPoint(x: 0.5, y: 1)
            ultraBlurMaskLayer.startPoint = CGPoint(x: 0.5, y: 0)
            ultraBlurMaskLayer.endPoint = CGPoint(x: 0.5, y: 1)
            hyperBlurMaskLayer.startPoint = CGPoint(x: 0.5, y: 0)
            hyperBlurMaskLayer.endPoint = CGPoint(x: 0.5, y: 1)
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
            layer.addSublayer(gradientLayer)
            update(
                height: 1,
                profileHeight: profileHeight,
                maxAlpha: maxAlpha,
                baseColor: baseColor,
                tuning: tuning
            )
        }

        required init?(coder: NSCoder) { fatalError() }

        /// Updates both the adaptive fade profile and the gradient layer frame.
        func update(
            height: CGFloat,
            profileHeight: CGFloat,
            maxAlpha: CGFloat,
            baseColor: UIColor,
            tuning: EdgeShadowTuning
        ) {
            updateGradient(
                height: height,
                profileHeight: profileHeight,
                maxAlpha: maxAlpha,
                baseColor: baseColor,
                tuning: tuning
            )
            updateHeight(height)
        }

        private func updateGradient(
            height: CGFloat,
            profileHeight: CGFloat,
            maxAlpha: CGFloat,
            baseColor: UIColor,
            tuning: EdgeShadowTuning
        ) {
            let clampedAlpha = min(max(maxAlpha, 0), 1)
            let profile = _AdaptiveGradientProfile.make(
                totalHeight: height,
                profileHeight: profileHeight,
                direction: direction,
                tuning: tuning
            )
            let blurScale = max(tuning.blurOpacityScale, 0)
            let primaryBlurOpacity = clampedAlpha * _blurRamp(blurScale, start: 0.0, end: 0.72)
            let boostBlurOpacity = clampedAlpha * _blurRamp(blurScale, start: 0.18, end: 0.88) * 0.84
            let maxBoostBlurOpacity = clampedAlpha * _blurRamp(blurScale, start: 0.48, end: 1.02) * 0.74
            let extremeBlurOpacity = clampedAlpha * _blurRamp(blurScale, start: 0.82, end: 1.26) * 0.64
            let ultraBlurOpacity = clampedAlpha * _blurRamp(blurScale, start: 1.00, end: 1.42) * 0.56
            let hyperBlurOpacity = clampedAlpha * _blurRamp(blurScale, start: 1.12, end: 1.60) * 0.48
            let tintOpacity = min(clampedAlpha * tuning.tintOpacityScale, 1)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            blurView.alpha = primaryBlurOpacity
            boostBlurView.alpha = boostBlurOpacity
            maxBoostBlurView.alpha = maxBoostBlurOpacity
            extremeBlurView.alpha = extremeBlurOpacity
            ultraBlurView.alpha = ultraBlurOpacity
            hyperBlurView.alpha = hyperBlurOpacity
            blurMaskLayer.locations = profile.locations
            blurMaskLayer.colors = profile.alphaFactors.map {
                UIColor.black.withAlphaComponent($0).cgColor
            }
            boostBlurMaskLayer.locations = profile.locations
            boostBlurMaskLayer.colors = profile.alphaFactors.map {
                UIColor.black.withAlphaComponent($0).cgColor
            }
            maxBoostBlurMaskLayer.locations = profile.locations
            maxBoostBlurMaskLayer.colors = profile.alphaFactors.map {
                UIColor.black.withAlphaComponent($0).cgColor
            }
            extremeBlurMaskLayer.locations = profile.locations
            extremeBlurMaskLayer.colors = profile.alphaFactors.map {
                UIColor.black.withAlphaComponent($0).cgColor
            }
            ultraBlurMaskLayer.locations = profile.locations
            ultraBlurMaskLayer.colors = profile.alphaFactors.map {
                UIColor.black.withAlphaComponent($0).cgColor
            }
            hyperBlurMaskLayer.locations = profile.locations
            hyperBlurMaskLayer.colors = profile.alphaFactors.map {
                UIColor.black.withAlphaComponent($0).cgColor
            }
            gradientLayer.locations = profile.locations
            gradientLayer.colors = profile.alphaFactors.map {
                baseColor.withAlphaComponent($0 * tintOpacity).cgColor
            }
            CATransaction.commit()
        }

        private func updateHeight(_ height: CGFloat) {
            guard height > 0 else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            blurView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
            boostBlurView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
            maxBoostBlurView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
            extremeBlurView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
            ultraBlurView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
            hyperBlurView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
            blurMaskLayer.frame = blurView.bounds
            boostBlurMaskLayer.frame = boostBlurView.bounds
            maxBoostBlurMaskLayer.frame = maxBoostBlurView.bounds
            extremeBlurMaskLayer.frame = extremeBlurView.bounds
            ultraBlurMaskLayer.frame = ultraBlurView.bounds
            hyperBlurMaskLayer.frame = hyperBlurView.bounds
            gradientLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
            CATransaction.commit()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard gradientLayer.frame.height > 0 else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            blurView.frame.size.width = bounds.width
            boostBlurView.frame.size.width = bounds.width
            maxBoostBlurView.frame.size.width = bounds.width
            extremeBlurView.frame.size.width = bounds.width
            ultraBlurView.frame.size.width = bounds.width
            hyperBlurView.frame.size.width = bounds.width
            blurMaskLayer.frame = blurView.bounds
            boostBlurMaskLayer.frame = boostBlurView.bounds
            maxBoostBlurMaskLayer.frame = maxBoostBlurView.bounds
            extremeBlurMaskLayer.frame = extremeBlurView.bounds
            ultraBlurMaskLayer.frame = ultraBlurView.bounds
            hyperBlurMaskLayer.frame = hyperBlurView.bounds
            gradientLayer.frame.size.width = bounds.width
            CATransaction.commit()
        }
    }
}

private func _blurRamp(_ value: CGFloat, start: CGFloat, end: CGFloat) -> CGFloat {
    guard end > start else { return value >= end ? 1 : 0 }
    let normalized = min(max((value - start) / (end - start), 0), 1)
    return _smootherStep(normalized)
}

private final class _TransparentBackdropBlurView: UIVisualEffectView {
    init(effect: UIBlurEffect) {
        super.init(effect: effect)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            DispatchQueue.main.async {
                self.refreshBackdropFilters()
            }
        }
        refreshBackdropFilters()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshBackdropFilters()
    }

    private func refreshBackdropFilters() {
        guard let filterLayer = layer.sublayers?.first else { return }
        filterLayer.filters = []
    }
}
