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
    var maxBlurRadius: CGFloat = 2.92
    var fadeExtension: CGFloat = 54
    var tintOpacityTop: Double = 1
    var tintOpacityMiddle: Double = 0
    var tintEdgeHeight: CGFloat = 87
    var startOffset: CGFloat = 0

    static let quizFlashDefault = ScreenTopProgressiveBlurConfiguration()
    static let tabBarDefault = ScreenTopProgressiveBlurConfiguration(
        maxBlurRadius: 0,
        fadeExtension: 0,
        tintOpacityTop: 1,
        tintOpacityMiddle: 0,
        tintEdgeHeight: 73,
        startOffset: 0
    )
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
            let tintEndLocation = min(max(configuration.tintEdgeHeight / max(blurHeight, 1), 0), 1)

            let overlay = overlayContainer(
                blurHeight: blurHeight,
                tintEndLocation: tintEndLocation
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
        tintEndLocation: CGFloat
    ) -> some View {
        if fillsContainer {
            VStack(spacing: 0) {
                if edge == .bottom {
                    Spacer(minLength: 0)
                }

                overlayBody(blurHeight: blurHeight, tintEndLocation: tintEndLocation)

                if edge == .top {
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: containerAlignment)
        } else {
            overlayBody(blurHeight: blurHeight, tintEndLocation: tintEndLocation)
        }
    }

    @ViewBuilder
    private func overlayBody(
        blurHeight: CGFloat,
        tintEndLocation: CGFloat
    ) -> some View {
        StableVariableBlurView(
            maxBlurRadius: configuration.maxBlurRadius,
            direction: variableBlurDirection,
            startOffset: configuration.startOffset
        )
        .frame(maxWidth: .infinity)
        .frame(height: blurHeight, alignment: containerAlignment)
        .overlay {
            tintGradient(tintEndLocation: tintEndLocation)
        }
        .ignoresSafeArea(.all, edges: ignoredSafeAreaEdges)
    }

    private func tintGradient(tintEndLocation: CGFloat) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: tintColor.opacity(configuration.tintOpacityTop), location: 0),
                .init(color: tintColor.opacity(0), location: tintEndLocation),
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
    let startOffset: CGFloat

    func makeUIView(context: Context) -> StableVariableBlurUIView {
        StableVariableBlurUIView(
            maxBlurRadius: maxBlurRadius,
            direction: direction,
            startOffset: startOffset
        )
    }

    func updateUIView(_ uiView: StableVariableBlurUIView, context: Context) {
        uiView.update(
            maxBlurRadius: maxBlurRadius,
            direction: direction,
            startOffset: startOffset
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
    private var currentStartOffset: CGFloat
    private var currentMaskPixelSize: CGSize = .zero
    private var currentDisplayScale: CGFloat = 0

    init(
        maxBlurRadius: CGFloat,
        direction: StableVariableBlurDirection,
        startOffset: CGFloat
    ) {
        self.currentDirection = direction
        self.currentMaxBlurRadius = -1
        self.currentStartOffset = startOffset
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
        updateBackdropScale()
        refreshMaskImage(force: true)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        configureFilterIfNeeded()
        updateBackdropScale()
        refreshMaskImage(force: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateBackdropScale()
        refreshMaskImage(force: false)
    }

    func update(
        maxBlurRadius: CGFloat,
        direction: StableVariableBlurDirection,
        startOffset: CGFloat
    ) {
        if currentDirection != direction {
            currentDirection = direction
            refreshMaskImage(force: true)
        }

        if abs(currentStartOffset - startOffset) > 0.001 {
            currentStartOffset = startOffset
            refreshMaskImage(force: true)
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
        rebuildFilter()
    }

    private func rebuildFilter() {
        backdropLayer?.filters = nil
        variableBlurFilter = nil
        configureFilterIfNeeded()
        backdropLayer?.setNeedsDisplay()
        backdropLayer?.setNeedsLayout()
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

        filter.setValue(true, forKey: normalizeEdgesKey)

        let layer = subviews.first?.layer
        layer?.filters = [filter]
        backdropLayer = layer
        variableBlurFilter = filter
        updateBackdropScale()
        filter.setValue(currentMaxBlurRadius, forKey: radiusKey)
        refreshMaskImage(force: true)
    }

    private func updateBackdropScale() {
        let scale = resolvedDisplayScale
        guard currentDisplayScale != scale else { return }
        currentDisplayScale = scale
        backdropLayer?.setValue(scale, forKey: "scale")
    }

    private var resolvedDisplayScale: CGFloat {
        let scale = window?.screen.scale ?? traitCollection.displayScale
        return max(scale, 1)
    }

    private func refreshMaskImage(force: Bool) {
        guard let variableBlurFilter else { return }

        let scale = resolvedDisplayScale
        let pixelSize = CGSize(
            width: max((bounds.width * scale).rounded(.up), 1),
            height: max((bounds.height * scale).rounded(.up), 1)
        )

        guard force || pixelSize != currentMaskPixelSize || scale != currentDisplayScale else {
            return
        }

        currentMaskPixelSize = pixelSize
        currentDisplayScale = scale
        variableBlurFilter.setValue(
            makeGradientImage(
                pixelWidth: pixelSize.width,
                pixelHeight: pixelSize.height,
                startOffset: currentStartOffset,
                direction: currentDirection
            ),
            forKey: maskKey
        )
        backdropLayer?.setNeedsDisplay()
        backdropLayer?.setNeedsLayout()
    }

    private func makeGradientImage(
        pixelWidth: CGFloat,
        pixelHeight: CGFloat,
        startOffset: CGFloat,
        direction: StableVariableBlurDirection
    ) -> CGImage {
        let clearTailOffset = min(max(startOffset, 0), 0.45)
        let gradientFilter = CIFilter.smoothLinearGradient()
        gradientFilter.color0 = CIColor.black
        gradientFilter.color1 = CIColor.clear

        switch direction {
        case .blurredTopClearBottom:
            gradientFilter.point0 = CGPoint(x: 0, y: pixelHeight)
            gradientFilter.point1 = CGPoint(x: 0, y: clearTailOffset * pixelHeight)
        case .blurredBottomClearTop:
            gradientFilter.point0 = CGPoint(x: 0, y: 0)
            gradientFilter.point1 = CGPoint(x: 0, y: pixelHeight - (clearTailOffset * pixelHeight))
        }

        return Self.gradientContext.createCGImage(
            gradientFilter.outputImage!,
            from: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
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
