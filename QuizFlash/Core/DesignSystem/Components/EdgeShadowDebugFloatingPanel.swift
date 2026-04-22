//
//  EdgeShadowDebugFloatingPanel.swift
//  QuizFlash
//
//  Reusable floating controls for per-screen edge-shadow tuning.
//

import SwiftUI

#if DEBUG
enum TopChromeDebugPanelMode {
    case shadow
    case progressiveBlur
}

struct EdgeShadowDebugFloatingPanel: View {
    @Environment(AppPreferences.self) private var appPreferences

    let mode: TopChromeDebugPanelMode
    @Binding var settings: EdgeShadowDebugSettings
    let onReset: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .trailing, spacing: UIConstants.Spacing.small) {
            if isExpanded {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    HStack {
                        Text(panelTitle)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                        Spacer()
                        Button(localized("Reset")) {
                            onReset()
                        }
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .buttonStyle(.plain)
                    }

                    switch mode {
                    case .shadow:
                        shadowControls
                    case .progressiveBlur:
                        progressiveBlurControls
                    }

                    Toggle(localized("Custom Color"), isOn: usesCustomColorBinding)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .tint(.purple)

                    if settings.colorOverride != nil {
                        ColorPicker(
                            colorPickerTitle,
                            selection: customColorBinding,
                            supportsOpacity: false
                        )
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                    }
                }
                .padding(UIConstants.Spacing.medium)
                .frame(width: 280)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
            }

            Button {
                withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
                    isExpanded.toggle()
                }
            } label: {
                Label(isExpanded ? hideButtonTitle : showButtonTitle, systemImage: "slider.horizontal.3")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .padding(.horizontal, UIConstants.Spacing.medium)
                    .padding(.vertical, UIConstants.Spacing.small)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var shadowControls: some View {
        sliderRow(
            title: "Alpha",
            value: binding(for: \.maxAlpha),
            range: 0.30...1.00
        )
        sliderRow(
            title: "Blur",
            value: binding(for: \.blurOpacityScale),
            range: 0.20...1.60
        )
        sliderRow(
            title: "Tint",
            value: binding(for: \.tintOpacityScale),
            range: 0.20...1.40
        )
        sliderRow(
            title: "Spread",
            value: binding(for: \.fadeLengthScale),
            range: 0.45...1.35
        )
        sliderRow(
            title: "Curve",
            value: binding(for: \.curveExponentBase),
            range: 0.70...1.80
        )
        sliderRow(
            title: "Height",
            value: binding(for: \.heightOffset),
            range: -60...60,
            format: "%.0f"
        )
    }

    @ViewBuilder
    private var progressiveBlurControls: some View {
        sliderRow(
            title: "Radius",
            value: binding(for: \.progressiveBlurRadius),
            range: 0...24
        )
        sliderRow(
            title: "Fade",
            value: binding(for: \.progressiveFadeExtension),
            range: 0...180,
            format: "%.0f"
        )
        sliderRow(
            title: "Top Tint",
            value: binding(for: \.progressiveTintOpacityTop),
            range: 0...1
        )
        sliderRow(
            title: "Mid Tint",
            value: binding(for: \.progressiveTintOpacityMiddle),
            range: 0...1
        )
        sliderRow(
            title: "Height",
            value: binding(for: \.heightOffset),
            range: -60...60,
            format: "%.0f"
        )
    }

    private func binding(for keyPath: WritableKeyPath<EdgeShadowDebugSettings, CGFloat>) -> Binding<CGFloat> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0 }
        )
    }

    private var panelTitle: String {
        switch mode {
        case .shadow:
            return localized("Shadow Tuner")
        case .progressiveBlur:
            return localized("Blur Tuner")
        }
    }

    private var showButtonTitle: String {
        switch mode {
        case .shadow:
            return localized("Tune Shadow")
        case .progressiveBlur:
            return localized("Tune Blur")
        }
    }

    private var hideButtonTitle: String {
        switch mode {
        case .shadow:
            return localized("Hide Shadow")
        case .progressiveBlur:
            return localized("Hide Blur")
        }
    }

    private var colorPickerTitle: String {
        switch mode {
        case .shadow:
            return localized("Shadow Color")
        case .progressiveBlur:
            return localized("Blur Color")
        }
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: appPreferences.resolvedLocale)
    }

    private func sliderRow(
        title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        format: String = "%.2f"
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: format, Double(value.wrappedValue)))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = CGFloat($0) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound)
            )
        }
    }

    private var usesCustomColorBinding: Binding<Bool> {
        Binding(
            get: { settings.colorOverride != nil },
            set: { isEnabled in
                settings.colorOverride = isEnabled ? EdgeShadowDebugColor(color: settings.resolvedColor) : nil
            }
        )
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { settings.resolvedColor },
            set: { settings.colorOverride = EdgeShadowDebugColor(color: $0) }
        )
    }
}
#endif
