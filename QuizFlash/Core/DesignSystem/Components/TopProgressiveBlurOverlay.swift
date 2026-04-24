//
//  TopProgressiveBlurOverlay.swift
//  QuizFlash
//
//  Real-time backdrop blur treatment for top floating chrome.
//

import SwiftUI
import VariableBlur

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

    private var clampedRevealProgress: CGFloat {
        min(max(revealProgress, 0), 1)
    }

    var body: some View {
        if topHeight > 0 {
            let totalHeight = max(topHeight, 1)
            let featherHeight = min(max(configuration.fadeExtension, 0), totalHeight)
            let featherStart = max(0, 1 - (featherHeight / totalHeight))
            let middleLocation = featherStart > 0.001
                ? min(max(featherStart * 0.7, 0), 1)
                : 0.32

            VStack(spacing: 0) {
                overlayBody(
                    totalHeight: totalHeight,
                    featherStart: featherStart,
                    middleLocation: middleLocation
                )

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
            .opacity(clampedRevealProgress)
            .animation(
                CollapsibleTitleChromeMetrics.shadowFadeAnimation,
                value: clampedRevealProgress
            )
        }
    }

    @ViewBuilder
    private func overlayBody(
        totalHeight: CGFloat,
        featherStart: CGFloat,
        middleLocation: CGFloat
    ) -> some View {
        BackgroundBlurView(radius: configuration.maxBlurRadius)
            .mask {
                blurMask(featherStart: featherStart)
            }
            .overlay {
                tintGradient(middleLocation: middleLocation)
            }
            .frame(maxWidth: .infinity)
            .frame(height: totalHeight, alignment: .top)
            .ignoresSafeArea(.all, edges: .top)
    }

    private func blurMask(featherStart: CGFloat) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: .white, location: featherStart),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func tintGradient(middleLocation: CGFloat) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: tintColor.opacity(configuration.tintOpacityTop), location: 0),
                .init(color: tintColor.opacity(configuration.tintOpacityMiddle), location: middleLocation),
                .init(color: tintColor.opacity(0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
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
