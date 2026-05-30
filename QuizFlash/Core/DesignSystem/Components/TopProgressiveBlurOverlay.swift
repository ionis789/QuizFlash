//
//  TopProgressiveBlurOverlay.swift
//  QuizFlash
//
//  Real-time backdrop blur treatment for top floating chrome.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import QuartzCore

struct ScreenTopProgressiveBlurConfiguration {
    var maxBlurRadius: CGFloat = 5
    var fadeExtension: CGFloat = 54
    var tintOpacityTop: Double = 0.73
    var tintOpacityMiddle: Double = 0.47

    static let quizFlashDefault = ScreenTopProgressiveBlurConfiguration()
}

struct TopProgressiveBlurOverlay: View {
    let topHeight: CGFloat
    let revealProgress: CGFloat
    var tintColor: Color = Color(ThemeColorToken.backgroundPrimary.assetName)
    var configuration: ScreenTopProgressiveBlurConfiguration = .quizFlashDefault
    var revealAnimation: Animation? = CollapsibleTitleChromeMetrics.shadowFadeAnimation

    var body: some View {
        ScreenEdgeProgressiveBlurOverlay(
            edge: .top,
            height: topHeight,
            revealProgress: revealProgress,
            tintColor: tintColor,
            configuration: configuration,
            revealAnimation: revealAnimation
        )
    }
}

struct ScreenEdgeProgressiveBlurOverlay: View {
    let edge: ScreenEdgeShadowEdge
    let height: CGFloat
    let revealProgress: CGFloat
    var tintColor: Color = Color(ThemeColorToken.backgroundPrimary.assetName)
    var configuration: ScreenTopProgressiveBlurConfiguration = .quizFlashDefault
    var revealAnimation: Animation? = CollapsibleTitleChromeMetrics.shadowFadeAnimation
    var fillsContainer: Bool = true

    private var clampedRevealProgress: CGFloat {
        min(max(revealProgress, 0), 1)
    }

    var body: some View {
        if height > 0, clampedRevealProgress > 0.001 {
            let totalHeight = max(height, 1)
            let blurHeight = totalHeight + max(configuration.fadeExtension, 0)
            let middleLocation = min(max(totalHeight / max(blurHeight, 1), 0), 1)

            let overlay = overlayContainer(
                blurHeight: blurHeight,
                middleLocation: middleLocation
            )
                .ignoresSafeArea(.all, edges: ignoredSafeAreaEdges)
                .allowsHitTesting(false)
                .opacity(clampedRevealProgress)

            if let revealAnimation {
                overlay.animation(revealAnimation, value: clampedRevealProgress)
            } else {
                overlay
            }
        }
    }

    @ViewBuilder
    private func overlayContainer(
        blurHeight: CGFloat,
        middleLocation: CGFloat
    ) -> some View {
        if fillsContainer {
            VStack(spacing: 0) {
                if edge == .bottom {
                    Spacer(minLength: 0)
                }

                overlayBody(blurHeight: blurHeight, middleLocation: middleLocation)

                if edge == .top {
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: containerAlignment)
        } else {
            overlayBody(blurHeight: blurHeight, middleLocation: middleLocation)
        }
    }

    @ViewBuilder
    private func overlayBody(
        blurHeight: CGFloat,
        middleLocation: CGFloat
    ) -> some View {
        StableVariableBlurView(
            maxBlurRadius: configuration.maxBlurRadius,
            direction: variableBlurDirection
        )
            .frame(maxWidth: .infinity)
            .frame(height: blurHeight, alignment: containerAlignment)
            .overlay {
                tintGradient(middleLocation: middleLocation)
            }
            .ignoresSafeArea(.all, edges: ignoredSafeAreaEdges)
    }

    private func tintGradient(middleLocation: CGFloat) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: tintColor.opacity(configuration.tintOpacityTop), location: 0),
                .init(color: tintColor.opacity(configuration.tintOpacityMiddle), location: middleLocation),
                .init(color: tintColor.opacity(0), location: 1),
            ],
            startPoint: gradientStartPoint,
            endPoint: gradientEndPoint
        )
    }

    private var containerAlignment: Alignment {
        edge == .top ? .top : .bottom
    }

    private var ignoredSafeAreaEdges: Edge.Set {
        edge == .top ? .top : .bottom
    }

    private var gradientStartPoint: UnitPoint {
        edge == .top ? .top : .bottom
    }

    private var gradientEndPoint: UnitPoint {
        edge == .top ? .bottom : .top
    }

    private var variableBlurDirection: StableVariableBlurDirection {
        edge == .top ? .blurredTopClearBottom : .blurredBottomClearTop
    }
}

private enum StableVariableBlurDirection: Equatable {
    case blurredTopClearBottom
    case blurredBottomClearTop
}

private struct StableVariableBlurView: UIViewRepresentable {
    let maxBlurRadius: CGFloat
    let direction: StableVariableBlurDirection

    func makeUIView(context: Context) -> StableVariableBlurUIView {
        StableVariableBlurUIView(
            maxBlurRadius: maxBlurRadius,
            direction: direction
        )
    }

    func updateUIView(_ uiView: StableVariableBlurUIView, context: Context) {
        uiView.update(
            maxBlurRadius: maxBlurRadius,
            direction: direction
        )
    }

    static func dismantleUIView(_ uiView: StableVariableBlurUIView, coordinator: ()) {
        uiView.tearDown()
    }
}

private final class StableVariableBlurUIView: UIVisualEffectView {
    private static let gradientContext = CIContext()

    private let radiusKey = "inputRadius"
    private let maskKey = "inputMaskImage"
    private let normalizeEdgesKey = "inputNormalizeEdges"

    private weak var backdropLayer: CALayer?
    private var variableBlurFilter: NSObject?
    private var currentDirection: StableVariableBlurDirection
    private var currentMaxBlurRadius: CGFloat

    init(
        maxBlurRadius: CGFloat,
        direction: StableVariableBlurDirection
    ) {
        self.currentDirection = direction
        self.currentMaxBlurRadius = -1
        super.init(effect: UIBlurEffect(style: .regular))

        isUserInteractionEnabled = false
        configureFilterIfNeeded()
        setMaxBlurRadius(maxBlurRadius)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        configureFilterIfNeeded()
        guard let window else { return }
        backdropLayer?.setValue(window.traitCollection.displayScale, forKey: "scale")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        configureFilterIfNeeded()
    }

    func update(
        maxBlurRadius: CGFloat,
        direction: StableVariableBlurDirection
    ) {
        if currentDirection != direction {
            currentDirection = direction
            variableBlurFilter?.setValue(
                makeGradientImage(direction: direction),
                forKey: maskKey
            )
        }

        setMaxBlurRadius(maxBlurRadius)
    }

    func tearDown() {
        backdropLayer?.filters = nil
        backdropLayer = nil
        variableBlurFilter = nil
    }

    private func setMaxBlurRadius(_ maxBlurRadius: CGFloat) {
        guard abs(currentMaxBlurRadius - maxBlurRadius) > 0.01 else {
            return
        }

        currentMaxBlurRadius = maxBlurRadius
        variableBlurFilter?.setValue(NSNumber(value: Double(maxBlurRadius)), forKey: radiusKey)
    }

    private func configureFilterIfNeeded() {
        guard variableBlurFilter == nil else { return }

        for subview in subviews.dropFirst() {
            subview.alpha = 0
        }

        let className = String("retliFAC".reversed())
        guard let filterClass = NSClassFromString(className) as? NSObject.Type else {
            return
        }

        let selectorName = String(":epyThtiWretlif".reversed())
        guard let filter = filterClass
            .perform(NSSelectorFromString(selectorName), with: "variableBlur")
            .takeUnretainedValue() as? NSObject else {
            return
        }

        filter.setValue(NSNumber(value: Double(currentMaxBlurRadius)), forKey: radiusKey)
        filter.setValue(makeGradientImage(direction: currentDirection), forKey: maskKey)
        filter.setValue(true, forKey: normalizeEdgesKey)

        let layer = subviews.first?.layer
        layer?.filters = [filter]
        backdropLayer = layer
        variableBlurFilter = filter
    }

    private func makeGradientImage(
        width: CGFloat = 100,
        height: CGFloat = 100,
        direction: StableVariableBlurDirection
    ) -> CGImage {
        let gradientFilter = CIFilter.linearGradient()
        gradientFilter.color0 = CIColor.black
        gradientFilter.color1 = CIColor.clear

        switch direction {
        case .blurredTopClearBottom:
            gradientFilter.point0 = CGPoint(x: 0, y: height)
            gradientFilter.point1 = CGPoint(x: 0, y: 0)
        case .blurredBottomClearTop:
            gradientFilter.point0 = CGPoint(x: 0, y: 0)
            gradientFilter.point1 = CGPoint(x: 0, y: height)
        }

        return Self.gradientContext.createCGImage(
            gradientFilter.outputImage!,
            from: CGRect(x: 0, y: 0, width: width, height: height)
        )!
    }
}

struct BackgroundBlurView: UIViewRepresentable {
    let radius: CGFloat

    func makeUIView(context: Context) -> StableBackgroundBlurView {
        StableBackgroundBlurView(radius: radius)
    }

    func updateUIView(_ uiView: StableBackgroundBlurView, context: Context) {
        uiView.setBlurRadius(radius)
    }
}

final class StableBackgroundBlurView: UIVisualEffectView {
    private let keyPath = "filters.gaussianBlur.inputRadius"
    private weak var blurLayer: CALayer?

    var blurRadius: CGFloat {
        get { blurLayer?.value(forKeyPath: keyPath) as? CGFloat ?? 0 }
        set { blurLayer?.setValue(newValue as NSNumber, forKeyPath: keyPath) }
    }

    init(radius: CGFloat) {
        super.init(effect: UIBlurEffect(style: .regular))
        isUserInteractionEnabled = false
        backgroundColor = .clear
        configureBlurLayerIfNeeded()
        setBlurRadius(radius)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        configureBlurLayerIfNeeded()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        // Keep the blur layer stable. Reconfiguring filters during scroll-driven
        // updates is what previously caused runaway memory growth on iOS 17.
    }

    func setBlurRadius(_ radius: CGFloat) {
        if abs(blurRadius - radius) > 0.01 {
            blurRadius = radius
        }
    }

    private func configureBlurLayerIfNeeded() {
        guard blurLayer == nil else { return }

        for subview in subviews where subview.description.contains("VisualEffectSubview") {
            subview.isHidden = true
        }

        guard let sublayer = layer.sublayers?.first else { return }

        sublayer.backgroundColor = nil
        sublayer.isOpaque = false

        if let filters = sublayer.filters {
            sublayer.filters = filters.filter { "\($0)" == "gaussianBlur" }
        }

        blurLayer = sublayer
    }
}
