import SwiftUI
import UIKit

// MARK: - SwiftUI Modifier
public extension View {
    func telegramGlass(
        blurFraction: CGFloat = 0.4, // Telegram uses a deep blur. 0.4 is usually the sweet spot.
        tintColor: Color = Color.black.opacity(0.65) // Telegram's dark mode signature tint
    ) -> some View {
        self.background(
            TelegramBlurRepresentable(
                blurFraction: blurFraction,
                tintColor: tintColor
            )
            .ignoresSafeArea()
        )
    }
}

// MARK: - Representable
private struct TelegramBlurRepresentable: UIViewRepresentable {
    var blurFraction: CGFloat
    var tintColor: Color

    func makeUIView(context: Context) -> TelegramBlurView {
        TelegramBlurView(blurFraction: blurFraction, tintColor: UIColor(tintColor))
    }

    func updateUIView(_ uiView: TelegramBlurView, context: Context) {
        uiView.update(blurFraction: blurFraction, tintColor: UIColor(tintColor))
    }
}

// MARK: - The UIKit Engine
private final class TelegramBlurView: UIView {
    private let visualEffectView = UIVisualEffectView(effect: nil)
    private let colorOverlay = UIView()
    private var animator: UIViewPropertyAnimator?

    init(blurFraction: CGFloat, tintColor: UIColor) {
        super.init(frame: .zero)
        setup(blurFraction: blurFraction, tintColor: tintColor)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup(blurFraction: CGFloat, tintColor: UIColor) {
        backgroundColor = .clear
        clipsToBounds = true

        // 1. Setup Base Blur View
        visualEffectView.frame = bounds
        visualEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(visualEffectView)

        // 2. Setup Custom Tint Overlay (Replaces Apple's ugly gray layers)
        colorOverlay.frame = bounds
        colorOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(colorOverlay)

        update(blurFraction: blurFraction, tintColor: tintColor)
    }

    func update(blurFraction: CGFloat, tintColor: UIColor) {
        colorOverlay.backgroundColor = tintColor

        // Stop any existing animator
        animator?.stopAnimation(true)
        animator?.finishAnimation(at: .current)

        // Reset effect
        visualEffectView.effect = nil

        // Use .regular as the base because it has the most neutral color profile
        let effect = UIBlurEffect(style: .regular)

        animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak self] in
            self?.visualEffectView.effect = effect
        }
        
        animator?.pausesOnCompletion = true
        animator?.startAnimation()
        
        // Lock the blur radius
        animator?.fractionComplete = max(0.0, min(blurFraction, 1.0))

        // CRITICAL: Strip Apple's hidden tint layers on the next run loop
        DispatchQueue.main.async { [weak self] in
            self?.stripSystemTintLayers()
        }
    }

    private func stripSystemTintLayers() {
        // Apple injects hidden backdrop layers. The lowest layer is the actual blur engine.
        // The layers stacked on top of it are the brightness/contrast/color tints.
        // We find the subviews and make everything EXCEPT the actual blur backdrop invisible.
        for subview in visualEffectView.subviews {
            let className = String(describing: type(of: subview))
            // "_UIVisualEffectBackdropView" is the actual blur layer in iOS.
            // We want to hide the "_UIVisualEffectSubview" which contains the color filters.
            if className != "_UIVisualEffectBackdropView" {
                subview.alpha = 0
                subview.isHidden = true
            }
        }
    }

    deinit {
        animator?.stopAnimation(true)
    }
}
