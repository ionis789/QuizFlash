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
    let supportsTopEdge: Bool
    let supportsBottomEdge: Bool
    let bottomHeightBase: CGFloat?
    let heightRange: ClosedRange<CGFloat>
    let showsProgressiveBlurRadius: Bool
    let panelTitleOverride: String.LocalizationValue?
    let showButtonTitleOverride: String.LocalizationValue?
    let hideButtonTitleOverride: String.LocalizationValue?
    @Binding var settings: EdgeShadowDebugSettings
    let onReset: () -> Void

    @State private var isExpanded = false
    @State private var selectedEdge: ScreenEdgeShadowEdge = .top

    init(
        mode: TopChromeDebugPanelMode,
        supportsTopEdge: Bool = true,
        supportsBottomEdge: Bool = false,
        initialSelectedEdge: ScreenEdgeShadowEdge = .top,
        bottomHeightBase: CGFloat? = nil,
        heightRange: ClosedRange<CGFloat> = -180...240,
        showsProgressiveBlurRadius: Bool = false,
        panelTitleOverride: String.LocalizationValue? = nil,
        showButtonTitleOverride: String.LocalizationValue? = nil,
        hideButtonTitleOverride: String.LocalizationValue? = nil,
        settings: Binding<EdgeShadowDebugSettings>,
        onReset: @escaping () -> Void
    ) {
        self.mode = mode
        self.supportsTopEdge = supportsTopEdge
        self.supportsBottomEdge = supportsBottomEdge
        self.bottomHeightBase = bottomHeightBase
        self.heightRange = heightRange
        self.showsProgressiveBlurRadius = showsProgressiveBlurRadius
        self.panelTitleOverride = panelTitleOverride
        self.showButtonTitleOverride = showButtonTitleOverride
        self.hideButtonTitleOverride = hideButtonTitleOverride
        let resolvedInitialEdge: ScreenEdgeShadowEdge = supportsTopEdge ? initialSelectedEdge : .bottom
        self._selectedEdge = State(initialValue: resolvedInitialEdge)
        self._settings = settings
        self.onReset = onReset
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isExpanded {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { }
            }

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

                        edgeSelector
                        Toggle(localized("Enabled"), isOn: selectedEnabledBinding)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .tint(.purple)

                        if selectedEdgeEnabled {
                            switch mode {
                            case .shadow:
                                shadowControls
                            case .progressiveBlur:
                                progressiveBlurControls
                            }

                            Toggle(localized("Custom Color"), isOn: usesCustomColorBinding)
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .tint(.purple)

                            if selectedColorOverride != nil {
                                ColorPicker(
                                    colorPickerTitle,
                                    selection: customColorBinding,
                                    supportsOpacity: false
                                )
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                            }
                        }
                    }
                    .padding(UIConstants.Spacing.medium)
                    .frame(width: 280)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    @ViewBuilder
    private var shadowControls: some View {
        sliderRow(
            title: "Alpha",
            value: selectedEdge == .top ? binding(for: \.maxAlpha) : binding(for: \.bottomMaxAlpha),
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
            value: selectedHeightOffsetBinding,
            range: heightRange,
            format: "%.0f"
        )
    }

    @ViewBuilder
    private var progressiveBlurControls: some View {
        if showsProgressiveBlurRadius {
            sliderRow(
                title: "Radius",
                value: selectedEdge == .top ? binding(for: \.progressiveBlurRadius) : binding(for: \.bottomProgressiveBlurRadius),
                range: 0...24
            )
        }
        sliderRow(
            title: "Fade",
            value: selectedEdge == .top ? binding(for: \.progressiveFadeExtension) : binding(for: \.bottomProgressiveFadeExtension),
            range: 0...180,
            format: "%.0f"
        )
        sliderRow(
            title: "Tint",
            value: selectedProgressiveTintBinding,
            range: 0...1
        )
        sliderRow(
            title: "Height",
            value: selectedHeightOffsetBinding,
            range: heightRange,
            format: "%.0f"
        )
    }

    @ViewBuilder
    private var edgeSelector: some View {
        if supportsTopEdge, supportsBottomEdge {
            Picker(localized("Edge"), selection: $selectedEdge) {
                Text(localized("Top")).tag(ScreenEdgeShadowEdge.top)
                Text(localized("Bottom")).tag(ScreenEdgeShadowEdge.bottom)
            }
            .pickerStyle(.segmented)
        }
    }

    private func binding(for keyPath: WritableKeyPath<EdgeShadowDebugSettings, CGFloat>) -> Binding<CGFloat> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0 }
        )
    }

    private var selectedEdgeEnabled: Bool {
        selectedEdge == .top ? settings.topEnabled : settings.bottomEnabled
    }

    private var selectedEnabledBinding: Binding<Bool> {
        Binding(
            get: { selectedEdgeEnabled },
            set: { isEnabled in
                switch selectedEdge {
                case .top:
                    settings.topEnabled = isEnabled
                case .bottom:
                    settings.bottomEnabled = isEnabled
                }
            }
        )
    }

    private var selectedHeightOffsetBinding: Binding<CGFloat> {
        if selectedEdge == .bottom, let bottomHeightBase {
            return Binding(
                get: { max(0, bottomHeightBase + settings.bottomHeightOffset) },
                set: { settings.bottomHeightOffset = $0 - bottomHeightBase }
            )
        }

        return selectedEdge == .top
            ? binding(for: \.heightOffset)
            : binding(for: \.bottomHeightOffset)
    }

    private var selectedProgressiveTintBinding: Binding<CGFloat> {
        Binding(
            get: {
                selectedEdge == .top
                    ? settings.progressiveTintOpacityTop
                    : settings.bottomProgressiveTintOpacityEdge
            },
            set: { opacity in
                let middleOpacity = opacity * 0.64
                switch selectedEdge {
                case .top:
                    settings.progressiveTintOpacityTop = opacity
                    settings.progressiveTintOpacityMiddle = middleOpacity
                case .bottom:
                    settings.bottomProgressiveTintOpacityEdge = opacity
                    settings.bottomProgressiveTintOpacityMiddle = middleOpacity
                }
            }
        )
    }

    private var panelTitle: String {
        if let panelTitleOverride {
            return localized(panelTitleOverride)
        }

        switch mode {
        case .shadow:
            return localized("Shadow Tuner")
        case .progressiveBlur:
            return localized("Blur Tuner")
        }
    }

    private var showButtonTitle: String {
        if let showButtonTitleOverride {
            return localized(showButtonTitleOverride)
        }

        switch mode {
        case .shadow:
            return localized("Tune Shadow")
        case .progressiveBlur:
            return localized("Tune Blur")
        }
    }

    private var hideButtonTitle: String {
        if let hideButtonTitleOverride {
            return localized(hideButtonTitleOverride)
        }

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
        EdgeShadowTuningSliderRow(
            title: title,
            value: value,
            range: range,
            format: format
        )
    }

    private var usesCustomColorBinding: Binding<Bool> {
        Binding(
            get: { selectedColorOverride != nil },
            set: { isEnabled in
                let colorOverride = isEnabled ? EdgeShadowDebugColor(color: selectedResolvedColor) : nil
                switch selectedEdge {
                case .top:
                    settings.colorOverride = colorOverride
                case .bottom:
                    settings.bottomColorOverride = colorOverride
                }
            }
        )
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { selectedResolvedColor },
            set: { color in
                switch selectedEdge {
                case .top:
                    settings.colorOverride = EdgeShadowDebugColor(color: color)
                case .bottom:
                    settings.bottomColorOverride = EdgeShadowDebugColor(color: color)
                }
            }
        )
    }

    private var selectedColorOverride: EdgeShadowDebugColor? {
        selectedEdge == .top ? settings.colorOverride : settings.bottomColorOverride
    }

    private var selectedResolvedColor: Color {
        selectedEdge == .top ? settings.resolvedColor : settings.resolvedBottomColor
    }
}

private struct EdgeShadowTuningSliderRow: View {
    let title: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let format: String

    @State private var draftValue: CGFloat?

    private var displayedValue: CGFloat {
        draftValue ?? value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: format, Double(displayedValue)))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { Double(displayedValue) },
                    set: { draftValue = CGFloat($0) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                onEditingChanged: { isEditing in
                    if isEditing {
                        draftValue = value
                    } else if let draftValue {
                        value = draftValue
                        self.draftValue = nil
                    }
                }
            )
        }
    }
}
#endif
