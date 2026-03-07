import SwiftUI
import UIKit

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Public API
// ─────────────────────────────────────────────────────────────────────────────

public extension View {
    func glassEffect(
        cornerRadius: CGFloat = 60,
        magnification: CGFloat = 1.3,
        showSpecular: Bool = false,
        darkIntensity: CGFloat = 0.4
    ) -> some View {
        modifier(GlassEffectModifier(
            cornerRadius: cornerRadius,
            magnification: magnification,
            showSpecular: showSpecular,
            darkIntensity: darkIntensity
        ))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ViewModifier
// ─────────────────────────────────────────────────────────────────────────────

public struct GlassEffectModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let magnification: CGFloat
    let showSpecular: Bool
    let darkIntensity: CGFloat

    public func body(content: Content) -> some View {
        content.background(
            GlassRepresentable(
                cornerRadius: cornerRadius,
                magnification: magnification,
                isDark: colorScheme == .dark,
                showSpecular: showSpecular
            )
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - UIViewRepresentable
// ─────────────────────────────────────────────────────────────────────────────

private struct GlassRepresentable: UIViewRepresentable {
    let cornerRadius: CGFloat
    let magnification: CGFloat
    let isDark: Bool
    let showSpecular: Bool

    func makeUIView(context: Context) -> GlassUIView {
        GlassUIView(
            cornerRadius: cornerRadius,
            magnification: magnification,
            isDark: isDark,
            showSpecular: showSpecular
        )
    }
    func updateUIView(_ v: GlassUIView, context: Context) {
        v.configure(
            cornerRadius: cornerRadius,
            magnification: magnification,
            isDark: isDark,
            showSpecular: showSpecular
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - PurBlurView  (UIVisualEffectView subclass)
// ─────────────────────────────────────────────────────────────────────────────

final class PurBlurView: UIVisualEffectView {

    private var animator: UIViewPropertyAnimator?

    init() {
        super.init(effect: nil)
        isUserInteractionEnabled = false
        setupAnimator()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        animator?.stopAnimation(true)
    }

    private func setupAnimator() {
        animator?.stopAnimation(true)
        self.effect = nil

        animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak self] in
            self?.effect = UIBlurEffect(style: .regular)
        }

        animator?.startAnimation()
        animator?.pauseAnimation()
        animator?.fractionComplete = 0.1
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let animator = animator else { return }

        if animator.state == .inactive {
            setupAnimator()
        } else {
            animator.pauseAnimation()
            animator.fractionComplete = 0.1
        }

        stripTintImmediately()
    }

    private func stripTintImmediately() {
        for sub in subviews {
            let typeName = String(describing: type(of: sub))
            if typeName.contains("Subview") {
                sub.alpha = 0
                sub.layer.backgroundColor = UIColor.clear.cgColor
                sub.layer.opacity = 0
                zeroLayerTree(sub.layer)
            }
        }
    }

    private func zeroLayerTree(_ l: CALayer) {
        if type(of: l) == CALayer.self {
            l.backgroundColor = UIColor.clear.cgColor
            l.opacity = 0
        }
        l.sublayers?.forEach { zeroLayerTree($0) }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - GlassUIView  (container — owns blur + decorative layers)
// ─────────────────────────────────────────────────────────────────────────────

final class GlassUIView: UIView {

    private var cornerRadius: CGFloat
    private var magnification: CGFloat
    private var isDark: Bool
    private var showSpecular: Bool

    // ── Subviews / layers ────────────────────────────────────────────────────
    private let blurView    = PurBlurView()
    private let tintOverlay = UIView()
    private let specular    = CAGradientLayer()

    // ── Init ─────────────────────────────────────────────────────────────────
    init(cornerRadius: CGFloat, magnification: CGFloat, isDark: Bool, showSpecular: Bool = true) {
        self.cornerRadius  = cornerRadius
        self.magnification = magnification
        self.isDark        = isDark
        self.showSpecular  = showSpecular
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    // ── Build ─────────────────────────────────────────────────────────────────
    private func build() {
        backgroundColor = .clear
        clipsToBounds   = true

        // 1. Blur
        blurView.frame = bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(blurView)

        // 2. Dark tint overlay
        tintOverlay.frame = bounds
        tintOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tintOverlay.isUserInteractionEnabled = false
        addSubview(tintOverlay)

        // 3. Specular highlight
        specular.locations   = [0, 0.5]
        specular.startPoint  = CGPoint(x: 0.5, y: 0)
        specular.endPoint    = CGPoint(x: 0.5, y: 1)
        specular.compositingFilter = "screenBlendMode"
        layer.addSublayer(specular)

        applyMagnification()
        applyDecorColors()
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    private func applyMagnification() {
        blurView.transform = CGAffineTransform(scaleX: magnification, y: magnification)
    }

    private func applyDecorColors() {
        if showSpecular {
            let specTop = UIColor.white.withAlphaComponent(isDark ? 0.08 : 0.40)
            specular.colors = [specTop.cgColor, UIColor.clear.cgColor]
        } else {
            // No highlight line — used for full-width bars with cornerRadius: 0
            specular.colors = [UIColor.clear.cgColor, UIColor.clear.cgColor]
        }

        let tintAlpha: CGFloat = isDark ? 0.1 : 0.15
        tintOverlay.backgroundColor = UIColor.black.withAlphaComponent(tintAlpha)
    }

    // ── Layout ────────────────────────────────────────────────────────────────
    override func layoutSubviews() {
        super.layoutSubviews()

        let r = min(cornerRadius, bounds.height / 2)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        layer.cornerRadius = r
        layer.cornerCurve  = .continuous
        layer.masksToBounds = true

        specular.frame = CGRect(x: 0, y: 0,
                                width: bounds.width,
                                height: bounds.height * 0.30)
        specular.cornerRadius    = r
        specular.maskedCorners   = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        CATransaction.commit()
    }

    // ── Configure (called from SwiftUI on update) ─────────────────────────────
    func configure(cornerRadius: CGFloat, magnification: CGFloat, isDark: Bool, showSpecular: Bool) {
        let magChanged  = self.magnification != magnification
        let darkChanged = self.isDark        != isDark

        self.cornerRadius  = cornerRadius
        self.magnification = magnification
        self.isDark        = isDark
        self.showSpecular  = showSpecular

        if magChanged  { applyMagnification() }
        if darkChanged { applyDecorColors()   }
        setNeedsLayout()
    }

    // ── Hit testing ───────────────────────────────────────────────────────────
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
