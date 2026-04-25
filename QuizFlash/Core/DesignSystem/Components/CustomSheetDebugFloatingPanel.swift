//
//  CustomSheetDebugFloatingPanel.swift
//  QuizFlash
//
//  Reusable floating controls for global custom-sheet tuning.
//

import SwiftUI

#if DEBUG
struct CustomSheetDebugFloatingPanel: View {
    @Binding var settings: CustomSheetDebugSettings
    let onReset: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .trailing, spacing: UIConstants.Spacing.small) {
            if isExpanded {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                        HStack {
                            Text("Sheet Tuner")
                                .font(.system(.headline, design: .rounded, weight: .bold))
                            Spacer()
                            Button("Reset") {
                                onReset()
                            }
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .buttonStyle(.plain)
                        }

                        sliderRow(
                            title: "Backdrop Blur",
                            value: binding(for: \.backdropBlurRadius),
                            range: 0...32
                        )
                        sliderRow(
                            title: "Blur Radius",
                            value: binding(for: \.blurRadius),
                            range: 0...18
                        )
                        sliderRow(
                            title: "Blur Fade",
                            value: binding(for: \.blurFadeExtension),
                            range: 0...120,
                            format: "%.0f"
                        )
                        sliderRow(
                            title: "Top Tint",
                            value: binding(for: \.blurTintOpacityTop),
                            range: 0...1
                        )
                        sliderRow(
                            title: "Mid Tint",
                            value: binding(for: \.blurTintOpacityMiddle),
                            range: 0...1
                        )
                        sliderRow(
                            title: "Blur Height",
                            value: binding(for: \.blurAreaHeight),
                            range: 24...120,
                            format: "%.0f"
                        )
                        sliderRow(
                            title: "Scroll Reveal",
                            value: binding(for: \.topBlurRevealDistance),
                            range: 8...120,
                            format: "%.0f"
                        )
                        sliderRow(
                            title: "Top Inset",
                            value: binding(for: \.contentTopInset),
                            range: 0...80,
                            format: "%.0f"
                        )
                        sliderRow(
                            title: "Scrim",
                            value: binding(for: \.scrimOpacity),
                            range: 0...1
                        )
                    }
                }
                .padding(UIConstants.Spacing.medium)
                .frame(width: 300)
                .frame(maxHeight: 620)
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
                Label(isExpanded ? "Hide Sheet" : "Tune Sheet", systemImage: "slider.horizontal.3")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .padding(.horizontal, UIConstants.Spacing.medium)
                    .padding(.vertical, UIConstants.Spacing.small)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func binding(
        for keyPath: WritableKeyPath<CustomSheetDebugSettings, CGFloat>
    ) -> Binding<CGFloat> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0 }
        )
    }

    private func sliderRow(
        title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        format: String = "%.2f"
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer()
                Text(String(format: format, Double(value.wrappedValue)))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
            .frame(height: 18)

            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = CGFloat($0) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound)
            )
            .tint(.purple.opacity(0.72))
        }
        .frame(minHeight: 56, alignment: .top)
        .padding(.vertical, 2)
    }
}
#endif
