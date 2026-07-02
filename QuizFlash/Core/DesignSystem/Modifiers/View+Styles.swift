//
//  View+Styles.swift
//  QuizFlash
//
//  Shared surface treatments for flashcard and widget surfaces.
//

import SwiftUI

// MARK: - Shared Motion Presets

extension Animation {
    /// Shared spring used when bottom chrome swaps between the custom tab bar and selection bars.
    static var bottomChromeSpring: Animation {
        .spring(response: 0.36, dampingFraction: 0.92)
    }

    /// Shared spring used by circular selection and accent-tracking motion.
    ///
    /// Use this when the effect should feel like the app's circular control
    /// family: stable, soft, and slightly elastic without overshooting hard.
    static var circularSelectionSpring: Animation {
        .spring(response: 0.34, dampingFraction: 0.84)
    }

    /// Shared spring used by circular progress and ring-style reveal motion.
    static var circularProgressSpring: Animation {
        .spring(response: 0.9, dampingFraction: 0.84)
    }

    /// Shared spring used for compact selection-toolbar state changes.
    static var selectionToolbarSpring: Animation {
        .spring(response: 0.3, dampingFraction: 0.9)
    }

    /// Shared spring used by tab-item emphasis inside the floating tab bar.
    static var tabItemSpring: Animation {
        .spring(response: 0.32, dampingFraction: 0.9)
    }

    /// Shared animation used while a context-menu source compresses under the finger.
    static var contextMenuPressIn: Animation {
        .timingCurve(0.42, 0.0, 0.20, 1.0, duration: 0.22)
    }

    /// Shared animation used when a pending press is released before opening the menu.
    static var contextMenuPressOut: Animation {
        .easeOut(duration: 0.08)
    }

    /// Shared spring used for the initial preview lift.
    static var contextMenuLiftSpring: Animation {
        .circularProgressSpring.speed(4.3)
    }

    /// Shared spring used while the pressed source scales back to its final size.
    static var contextMenuPreviewScaleBackSpring: Animation {
        .circularProgressSpring.speed(2.8)
    }

    /// Shared spring used when the lifted preview settles into place.
    static var contextMenuSettleSpring: Animation {
        .circularProgressSpring.speed(3.9)
    }

    /// Shared spring used when the preview has to travel vertically to fit the menu.
    static var contextMenuPreviewPushSpring: Animation {
        .circularProgressSpring.speed(3.3)
    }

    /// Shared spring used while dismissing the custom context menu.
    static var contextMenuDismissSpring: Animation {
        .circularProgressSpring.speed(4.0)
    }

    /// Shared spring used by the context-menu card and row cascade.
    static var contextMenuMenuSpring: Animation {
        .circularProgressSpring.speed(4.0)
    }

    /// Shared spring used when the main context-menu card pops in under the source preview.
    static var contextMenuMenuPopSpring: Animation {
        .circularProgressSpring.speed(3.6)
    }
}

/// Wraps bottom-chrome state swaps in the shared animation transaction.
@MainActor
func withBottomChromeAnimation(_ updates: () -> Void) {
    withAnimation(.bottomChromeSpring, updates)
}

extension AnyTransition {
    /// Standard insertion/removal transition for floating bottom chrome.
    static var bottomChrome: AnyTransition {
        .move(edge: .bottom)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.96, anchor: .bottom))
    }
}

// MARK: - Brand Button Chrome

/// Semantic chrome roles supported by the shared brand button style.
enum QuizFlashButtonChrome {
    case primary
    case secondary
    case accentAlt
    case surface
}

/// Shared button shapes supported by the shared brand button style.
enum QuizFlashButtonShape {
    case capsule
    case circle
}

/// Applies the shared flat button chrome used across primary call-to-actions.
private struct QuizFlashBrandButtonStyle: ButtonStyle {
    @Environment(ThemeManager.self) private var themeManager

    let chrome: QuizFlashButtonChrome
    let shape: QuizFlashButtonShape
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor.opacity(configuration.isPressed ? 0.94 : 1))
            .padding(.horizontal, shape == .capsule ? 18 : 0)
            .frame(
                minWidth: shape == .circle ? size : nil,
                maxWidth: shape == .circle ? size : nil,
                minHeight: size,
                maxHeight: size
            )
            .background {
                backgroundFill(isPressed: configuration.isPressed)
            }
            .opacity(configuration.isPressed ? 0.92 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.timingCurve(0.24, 0.84, 0.30, 1.0, duration: 0.18), value: configuration.isPressed)
    }

    private var fillColor: Color {
        switch chrome {
        case .primary:
            themeManager.roleColor(.buttonPrimaryFill)
        case .secondary:
            themeManager.roleColor(.buttonSecondaryFill)
        case .accentAlt:
            themeManager.roleColor(.buttonDangerFill)
        case .surface:
            themeManager.roleColor(.buttonSurfaceFill)
        }
    }

    private var foregroundColor: Color {
        switch chrome {
        case .primary:
            themeManager.roleColor(.buttonPrimaryForeground)
        case .secondary:
            themeManager.roleColor(.buttonSecondaryForeground)
        case .accentAlt:
            themeManager.roleColor(.buttonDangerForeground)
        case .surface:
            themeManager.roleColor(.buttonSurfaceForeground)
        }
    }

    @ViewBuilder
    private func backgroundFill(isPressed: Bool) -> some View {
        switch shape {
        case .capsule:
            Capsule(style: .continuous)
                .fill(fillColor.opacity(isPressed ? 0.92 : 1))
        case .circle:
            Circle()
                .fill(fillColor.opacity(isPressed ? 0.92 : 1))
        }
    }
}

/// Applies the shared flat chrome to non-button content such as pills and labels.
private struct QuizFlashChromeModifier: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager

    let chrome: QuizFlashButtonChrome
    let shape: QuizFlashButtonShape
    let size: CGFloat
    let horizontalPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, shape == .capsule ? horizontalPadding : 0)
            .frame(
                minWidth: shape == .circle ? size : nil,
                maxWidth: shape == .circle ? size : nil,
                minHeight: size,
                maxHeight: size
            )
            .background {
                switch shape {
                case .capsule:
                    Capsule(style: .continuous)
                        .fill(fillColor)
                case .circle:
                    Circle()
                        .fill(fillColor)
                }
            }
    }

    private var fillColor: Color {
        switch chrome {
        case .primary:
            themeManager.roleColor(.labelPrimaryFill)
        case .secondary:
            themeManager.roleColor(.labelSecondaryFill)
        case .accentAlt:
            themeManager.roleColor(.labelDangerFill)
        case .surface:
            themeManager.roleColor(.labelSurfaceFill)
        }
    }

    private var foregroundColor: Color {
        switch chrome {
        case .primary:
            themeManager.roleColor(.labelPrimaryForeground)
        case .secondary:
            themeManager.roleColor(.labelSecondaryForeground)
        case .accentAlt:
            themeManager.roleColor(.labelDangerForeground)
        case .surface:
            themeManager.roleColor(.labelSurfaceForeground)
        }
    }
}

// MARK: - FlashcardSurfaceRole

/// Semantic surface roles supported by the shared flashcard/widget chrome modifier.
enum FlashcardSurfaceRole {
    case card
    case widget
}

// MARK: - Duo Surface Role

/// Shared Duolingo-inspired surface density used by widgets, panels, and controls.
enum DuoSurfaceRole {
    case panel
    case control
}

// MARK: - FlashcardSurfaceModifier

/// Applies the shared surface chrome used by flashcards and widget-like cards.
private struct FlashcardSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(ThemeManager.self) private var themeManager

    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    let surfaceRole: FlashcardSurfaceRole
    let baseBorderBlurRadius: CGFloat?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                shape
                    .fill(surfaceBackground)
                    .shadow(color: shadowColor, radius: shadowRadius, y: shadowYOffset)
            }
            .overlay {
                if surfaceRole == .card {
                    dynamicCardBorder(shape: shape)
                } else {
                    basePrimaryBorder(shape: shape)
                }
            }
            .overlay {
                if surfaceRole == .widget {
                    baseSecondaryBorder(shape: shape)
                }
            }
            .clipShape(shape)
    }

    private var surfaceBackground: AnyShapeStyle {
        switch surfaceRole {
        case .card:
            AnyShapeStyle(themeManager.roleColor(.cardSurfaceFill))
        case .widget:
            AnyShapeStyle(
                themeManager.roleColor(.widgetSurfaceFill)
                    .shadow(.inner(color: themeManager.textPrimary.opacity(colorScheme == .dark ? 0.035 : 0.08), radius: 1.2, x: 0, y: 0))
            )
        }
    }

    private var shadowColor: Color {
        switch surfaceRole {
        case .card:
            colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.12)
        case .widget:
            Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08)
        }
    }

    private var shadowYOffset: CGFloat {
        shadowRadius > 0 ? 8 : 0
    }

    private var basePrimaryBorderColor: Color {
        switch surfaceRole {
        case .card:
            themeManager.textPrimary.opacity(colorScheme == .dark ? 0.09 : 0.28)
        case .widget:
            themeManager.roleColor(.widgetSurfaceBorder).opacity(colorScheme == .dark ? 0.17 : 0.16)
        }
    }

    private var baseSecondaryBorderColor: Color {
        switch surfaceRole {
        case .card:
            themeManager.textPrimary.opacity(colorScheme == .dark ? 0.035 : 0.12)
        case .widget:
            themeManager.roleColor(.widgetSurfaceBorder).opacity(colorScheme == .dark ? 0.055 : 0.055)
        }
    }

    private var resolvedBaseBorderBlurRadius: CGFloat {
        max(0, baseBorderBlurRadius ?? defaultBaseBorderBlurRadius)
    }

    private var defaultBaseBorderBlurRadius: CGFloat {
        switch surfaceRole {
        case .card:
            2
        case .widget:
            0
        }
    }

    private var primaryBorderLineWidth: CGFloat {
        1 + min(resolvedBaseBorderBlurRadius * 0.08, 0.9)
    }

    private var secondaryBorderLineWidth: CGFloat {
        1 + min(resolvedBaseBorderBlurRadius * 0.04, 0.5)
    }

    private var secondaryBorderBlurRadius: CGFloat {
        resolvedBaseBorderBlurRadius * 0.58
    }

    private var resolvedFeedbackIntensity: CGFloat {
        0
    }

    private var cardBorderColor: Color {
        themeManager.textPrimary.opacity(colorScheme == .dark ? 0.11 : 0.30)
    }

    private var resolvedCardBorderLineWidth: CGFloat {
        1.08 + min(resolvedBaseBorderBlurRadius * 0.16, 0.65)
    }

    private var resolvedCardBorderBlurRadius: CGFloat {
        resolvedBaseBorderBlurRadius
    }

    private func basePrimaryBorder(shape: RoundedRectangle) -> some View {
        shape
            .stroke(basePrimaryBorderColor, lineWidth: primaryBorderLineWidth)
            .blur(radius: resolvedBaseBorderBlurRadius)
            .clipShape(shape)
    }

    private func baseSecondaryBorder(shape: RoundedRectangle) -> some View {
        shape
            .stroke(baseSecondaryBorderColor, lineWidth: secondaryBorderLineWidth)
            .blur(radius: secondaryBorderBlurRadius)
    }

    private func dynamicCardBorder(shape: RoundedRectangle) -> some View {
        shape
            .stroke(
                cardBorderColor,
                lineWidth: resolvedCardBorderLineWidth
            )
            .blur(radius: resolvedCardBorderBlurRadius)
            .clipShape(shape)
    }
}

// MARK: - DuoSurfaceModifier

/// Applies the shared Duolingo-inspired panel/control surface chrome.
private struct DuoSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(ThemeManager.self) private var themeManager

    let cornerRadius: CGFloat
    let role: DuoSurfaceRole
    let tint: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                shape
                    .fill(fillColor)
                    .overlay {
                        if let tint {
                            shape.fill(tint.opacity(role == .panel ? 0.025 : 0.018))
                        }
                    }
            }
            .overlay {
                shape
                    .strokeBorder(borderColor, lineWidth: borderLineWidth)
            }
            .clipShape(shape)
    }

    private var fillColor: Color {
        switch role {
        case .panel:
            themeManager.roleColor(.widgetSurfaceFill)
        case .control:
            themeManager.roleColor(.settingsCardFill).opacity(colorScheme == .dark ? 0.92 : 1)
        }
    }

    private var borderColor: Color {
        let baseOpacity: CGFloat = role == .panel ? 0.17 : 0.105
        return themeManager.roleColor(.widgetSurfaceBorder).opacity(colorScheme == .dark ? baseOpacity : baseOpacity * 0.86)
    }

    private var borderLineWidth: CGFloat {
        role == .panel ? 1 : 0.8
    }
}

// MARK: - DuoMetricPillModifier

/// Applies the shared outlined metric-chip treatment used by Home-style stats.
private struct DuoMetricPillModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(ThemeManager.self) private var themeManager

    let tint: Color?

    func body(content: Content) -> some View {
        content
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, UIConstants.Spacing.standard)
            .padding(.vertical, UIConstants.Spacing.small)
            .background {
                Capsule(style: .continuous)
                    .fill(fillColor)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1.05)
            }
    }

    private var fillColor: Color {
        (tint ?? themeManager.roleColor(.widgetSurfaceBorder)).opacity(colorScheme == .dark ? 0.035 : 0.055)
    }

    private var borderColor: Color {
        (tint ?? themeManager.roleColor(.widgetSurfaceBorder)).opacity(colorScheme == .dark ? 0.26 : 0.22)
    }
}

// MARK: - BorderBeamModifier

/// Applies a moving gradient highlight around a rounded surface.
private struct BorderBeamModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let border: Color
    let hideFadeBorder: Bool
    let beam: [Color]
    let beamBlur: CGFloat
    let cornerRadius: CGFloat
    let lineWidth: CGFloat
    let duration: TimeInterval
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if isEnabled {
                    if reduceMotion {
                        beamLayers(progress: 0.18)
                    } else {
                        KeyframeAnimator(initialValue: 0.0, repeating: true) { progress in
                            beamLayers(progress: progress)
                        } keyframes: { _ in
                            LinearKeyframe(1.0, duration: duration)
                        }
                    }
                } else if !hideFadeBorder {
                    shape
                        .stroke(border.opacity(0.22), lineWidth: lineWidth)
                }
            }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var resolvedBeam: [Color] {
        beam.isEmpty ? [border.opacity(0.95), border.opacity(0.18)] : beam
    }

    private func beamLayers(progress: Double) -> some View {
        let rotation = progress * 360
        let borderGradient = AngularGradient(
            colors: [.clear, border, .clear],
            center: .center,
            startAngle: .degrees(140 + rotation),
            endAngle: .degrees(270 + rotation)
        )
        let beamGradient = LinearGradient(
            colors: resolvedBeam,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        return ZStack {
            if !hideFadeBorder {
                shape
                    .stroke(border.opacity(0.22), lineWidth: lineWidth)
            }

            shape
                .fill(beamGradient)
                .mask {
                    Rectangle()
                        .overlay {
                            shape
                                .blur(radius: beamBlur)
                                .blendMode(.destinationOut)
                        }
                }
                .mask {
                    shape
                        .fill(borderGradient)
                        .blur(radius: beamBlur / 1.5)
                        .padding(-beamBlur * 2)
                }

            shape
                .stroke(borderGradient, lineWidth: lineWidth)
        }
        .padding(0.5)
        .allowsHitTesting(false)
    }
}

// MARK: - Press Effect Button Styles

/// Keeps button interaction semantics without changing the label while pressed.
private struct NoPressEffectButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// Button style for full-surface Duolingo-style panels.
private struct DuoPressableSurfaceStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// MARK: - TopNavigationChromeModifier

/// Applies the shared top-bar inset used by Deck, Create, and Library chrome.
private struct TopNavigationChromeModifier: ViewModifier {
    let horizontalInset: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontalInset)
            .padding(.top, UIConstants.Layout.deckNavigationTopPadding)
    }
}

// MARK: - StatusTextMotionModifier

/// Applies the shared springy numeric text transition used by live status and counter labels.
private struct StatusTextMotionModifier<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger

    func body(content: Content) -> some View {
        content
            .contentTransition(.numericText())
            .animation(.selectionToolbarSpring, value: trigger)
    }
}

// MARK: - BottomChromeVisibilityModifier

/// Applies the shared show/hide treatment for the floating tab bar and other persistent bottom chrome.
private struct BottomChromeVisibilityModifier: ViewModifier {
    let isVisible: Bool
    let hiddenOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : hiddenOffset)
            .scaleEffect(isVisible ? 1 : 0.98, anchor: .bottom)
            .allowsHitTesting(isVisible)
            .animation(.bottomChromeSpring, value: isVisible)
    }
}

private struct AppScreenBackgroundModifier: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager

    let style: AppScreenBackgroundStyle

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(themeManager.backgroundColor(for: style).ignoresSafeArea())
    }
}

// MARK: - View Extensions

extension View {
    /// Applies the shared QuizFlash button chrome for capsule and circular actions.
    func quizFlashButtonStyle(
        _ chrome: QuizFlashButtonChrome = .primary,
        shape: QuizFlashButtonShape = .capsule,
        size: CGFloat = UIConstants.Size.buttonHeight
    ) -> some View {
        buttonStyle(QuizFlashBrandButtonStyle(chrome: chrome, shape: shape, size: size))
    }

    /// Applies the shared flat pill chrome to labels and other non-button content.
    func quizFlashLabelChrome(
        _ chrome: QuizFlashButtonChrome = .surface,
        shape: QuizFlashButtonShape = .capsule,
        size: CGFloat = UIConstants.Size.buttonHeight,
        horizontalPadding: CGFloat = 18
    ) -> some View {
        modifier(
            QuizFlashChromeModifier(
                chrome: chrome,
                shape: shape,
                size: size,
                horizontalPadding: horizontalPadding
            )
        )
    }

    /// Applies the shared flashcard/widget chrome.
    func flashcardStyle(
        cornerRadius: CGFloat = 40,
        shadowRadius: CGFloat = 0,
        surfaceRole: FlashcardSurfaceRole = .card,
        baseBorderBlurRadius: CGFloat? = nil
    ) -> some View {
        modifier(
            FlashcardSurfaceModifier(
                cornerRadius: cornerRadius,
                shadowRadius: shadowRadius,
                surfaceRole: surfaceRole,
                baseBorderBlurRadius: baseBorderBlurRadius
            )
        )
    }

    /// Applies the shared Duolingo-inspired panel chrome.
    func duoSurface(
        cornerRadius: CGFloat = UIConstants.Radius.maximum,
        tint: Color? = nil
    ) -> some View {
        modifier(DuoSurfaceModifier(cornerRadius: cornerRadius, role: .panel, tint: tint))
    }

    /// Applies the denser shared chrome for rows and grouped controls.
    func duoControlSurface(
        cornerRadius: CGFloat = UIConstants.Radius.large,
        tint: Color? = nil
    ) -> some View {
        modifier(DuoSurfaceModifier(cornerRadius: cornerRadius, role: .control, tint: tint))
    }

    /// Applies the shared outlined metric-chip treatment.
    func duoMetricPill(tint: Color? = nil) -> some View {
        modifier(DuoMetricPillModifier(tint: tint))
    }

    /// Applies a moving gradient highlight around a rounded surface.
    func borderBeam(
        border: Color,
        hideFadeBorder: Bool = true,
        beam: [Color],
        beamBlur: CGFloat,
        cornerRadius: CGFloat,
        lineWidth: CGFloat = 0.8,
        duration: TimeInterval = 2.5,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            BorderBeamModifier(
                border: border,
                hideFadeBorder: hideFadeBorder,
                beam: beam,
                beamBlur: beamBlur,
                cornerRadius: cornerRadius,
                lineWidth: lineWidth,
                duration: duration,
                isEnabled: isEnabled
            )
        )
    }

    /// Applies the purple AI-generation beam used on primary generation surfaces.
    func aiGenerationBorderBeam(
        accent: Color,
        cornerRadius: CGFloat,
        beamBlur: CGFloat = 12,
        lineWidth: CGFloat = 1,
        duration: TimeInterval = 2.7,
        isEnabled: Bool = true
    ) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            accent.opacity(isEnabled ? 0.42 : 0.20),
                            Color.white.opacity(isEnabled ? 0.18 : 0.08),
                            accent.opacity(isEnabled ? 0.30 : 0.14),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(1, lineWidth * 0.72)
                )
                .allowsHitTesting(false)
        }
        .borderBeam(
            border: accent.opacity(0.92),
            hideFadeBorder: false,
            beam: [
                accent.opacity(0.96),
                accent.opacity(0.42),
                Color.white.opacity(0.72),
                accent.opacity(0.92)
            ],
            beamBlur: beamBlur,
            cornerRadius: cornerRadius,
            lineWidth: lineWidth,
            duration: duration,
            isEnabled: isEnabled
        )
    }

    /// Removes visual press feedback while preserving button behavior.
    func noPressEffectButtonStyle() -> some View {
        buttonStyle(NoPressEffectButtonStyle())
    }

    /// Applies the shared full-panel button style.
    func duoPressableSurfaceStyle() -> some View {
        buttonStyle(DuoPressableSurfaceStyle())
    }

    /// Applies the standard top chrome positioning shared by navigation surfaces.
    func topNavigationChrome(horizontalInset: CGFloat = UIConstants.Layout.compactScreenEdgeInset) -> some View {
        modifier(TopNavigationChromeModifier(horizontalInset: horizontalInset))
    }

    /// Applies the shared animated status-label treatment for counters and short live state text.
    func statusTextMotion<Trigger: Equatable>(trigger: Trigger) -> some View {
        modifier(StatusTextMotionModifier(trigger: trigger))
    }

    /// Applies the standard visibility motion used when bottom chrome appears or yields to selection bars.
    func bottomChromeVisibility(_ isVisible: Bool, hiddenOffset: CGFloat = 80) -> some View {
        modifier(BottomChromeVisibilityModifier(isVisible: isVisible, hiddenOffset: hiddenOffset))
    }

    /// Applies the app-level screen background so root surfaces do not fall back to UIKit system greys during resize.
    func appScreenBackground(_ style: AppScreenBackgroundStyle = .primary) -> some View {
        modifier(AppScreenBackgroundModifier(style: style))
    }
}
