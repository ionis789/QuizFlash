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
    var revealAnimation: Animation? = CollapsibleTitleChromeMetrics.shadowFadeAnimation

    private var clampedRevealProgress: CGFloat {
        min(max(revealProgress, 0), 1)
    }

    var body: some View {
        if topHeight > 0, clampedRevealProgress > 0.001 {
            let totalHeight = max(topHeight, 1)
            let blurHeight = totalHeight + max(configuration.fadeExtension, 0)
            let middleLocation = min(max(totalHeight / max(blurHeight, 1), 0), 1)

            let overlay = VStack(spacing: 0) {
                overlayBody(
                    blurHeight: blurHeight,
                    middleLocation: middleLocation
                )

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
    private func overlayBody(
        blurHeight: CGFloat,
        middleLocation: CGFloat
    ) -> some View {
        VariableBlurView(
            maxBlurRadius: configuration.maxBlurRadius,
            direction: .blurredTopClearBottom
        )
            .id(variableBlurIdentity)
            .frame(maxWidth: .infinity)
            .frame(height: blurHeight, alignment: .top)
            .overlay {
                tintGradient(middleLocation: middleLocation)
            }
            .ignoresSafeArea(.all, edges: .top)
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

    private var variableBlurIdentity: VariableBlurIdentity {
        VariableBlurIdentity(
            maxBlurRadius: configuration.maxBlurRadius
        )
    }
}

private struct VariableBlurIdentity: Hashable {
    let maxBlurRadius: CGFloat
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
