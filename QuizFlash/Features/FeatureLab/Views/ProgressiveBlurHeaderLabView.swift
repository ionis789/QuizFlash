//
//  ProgressiveBlurHeaderLabView.swift
//  QuizFlash
//
//  Sandbox for the ProgressiveBlurHeader package.
//

import ProgressiveBlurHeader
import SwiftUI

struct ProgressiveBlurHeaderLabView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var settings = ProgressiveBlurHeaderLabSettings.default

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            StickyBlurHeader(
                maxBlurRadius: settings.maxBlurRadius.cgFloat,
                fadeExtension: settings.fadeExtension.cgFloat,
                tintOpacityTop: settings.tintOpacityTop,
                tintOpacityMiddle: settings.tintOpacityMiddle
            ) {
                header
            } content: {
                content
            }
            .background(Color(ThemeColorToken.backgroundPrimary.assetName))

            floatingPanel
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: UIConstants.Spacing.medium) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.compact.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                Text("Blur Header Lab")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white.opacity(0.96))

                Text("Radius \(settings.maxBlurRadius, specifier: "%.1f")")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))
            }

            Spacer(minLength: 0)

            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                }
                .accessibilityHidden(true)
        }
        .padding(.horizontal, UIConstants.Spacing.large)
        .padding(.top, 8)
        .padding(.bottom, UIConstants.Spacing.medium)
    }

    private var content: some View {
        LazyVStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            heroCard

            ForEach(Array(demoRows.enumerated()), id: \.offset) { index, row in
                ProgressiveBlurHeaderDemoCard(
                    index: index + 1,
                    title: row.title,
                    subtitle: row.subtitle,
                    accent: row.accent
                )
            }

            Spacer(minLength: 220)
        }
        .padding(.horizontal, UIConstants.Spacing.large)
        .padding(.top, UIConstants.Spacing.medium)
        .padding(.bottom, 120)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            Text("Scroll this surface and watch the rows pass behind the sticky header blur.")
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(.white.opacity(0.96))
                .fixedSize(horizontal: false, vertical: true)

            Text("This lab is intentionally close to the package README: one sticky header, one scrolling stack, and live controls for the public parameters.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: UIConstants.Spacing.medium) {
                metricPill(title: "Blur", value: String(format: "%.1f", settings.maxBlurRadius))
                metricPill(title: "Fade", value: String(format: "%.0f", settings.fadeExtension))
                metricPill(title: "Tint", value: String(format: "%.2f", settings.tintOpacityTop))
            }
        }
        .padding(UIConstants.Spacing.large)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.54))

            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white.opacity(0.94))
        }
        .padding(.horizontal, UIConstants.Spacing.medium)
        .padding(.vertical, UIConstants.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var floatingPanel: some View {
        ProgressiveBlurHeaderLabFloatingPanel(
            settings: $settings,
            onReset: { settings = .default }
        )
        .padding(.trailing, UIConstants.Spacing.medium)
        .padding(.bottom, 104)
    }

    private var demoRows: [ProgressiveBlurHeaderDemoRowData] {
        [
            .init(title: "Deck Search Performance", subtitle: "Dense title styling and small metadata should make the blur transition obvious while scrolling.", accent: Color.cyan.opacity(0.8)),
            .init(title: "Background Primary Surface", subtitle: "Tests how the package tint behaves on the same dark surface language used in the app.", accent: Color.mint.opacity(0.8)),
            .init(title: "Collapsible Chrome Handoff", subtitle: "Useful reference if we later compare this package against the current edge shadow and compact title stack.", accent: Color.orange.opacity(0.85)),
            .init(title: "Library Header Stress", subtitle: "Longer titles, separators, and mixed contrast help expose artifacts quickly in screenshots.", accent: Color.purple.opacity(0.8)),
            .init(title: "Scroll Through Repeated Cards", subtitle: "The goal here is simple: no clipping, no fake snapshot, just live content blurring underneath.", accent: Color.green.opacity(0.75)),
            .init(title: "Package API Check", subtitle: "Only the public knobs from StickyBlurHeader are exposed in the tuner on purpose.", accent: Color.blue.opacity(0.8)),
        ]
    }
}

private struct ProgressiveBlurHeaderDemoCard: View {
    let index: Int
    let title: String
    let subtitle: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(accent)
                .frame(width: 120, height: 8)

            Text(title)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white.opacity(0.96))
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .overlay(Color.white.opacity(0.08))

            Text("Row \(index)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.46))
        }
        .padding(UIConstants.Spacing.large)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }
}

private struct ProgressiveBlurHeaderLabFloatingPanel: View {
    @Binding var settings: ProgressiveBlurHeaderLabSettings
    let onReset: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .trailing, spacing: UIConstants.Spacing.small) {
            if isExpanded {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    HStack {
                        Text("Header Blur")
                            .font(.system(.headline, weight: .bold))

                        Spacer()

                        Button("Reset") {
                            onReset()
                        }
                        .font(.system(.caption, weight: .semibold))
                        .buttonStyle(.plain)
                    }

                    sliderRow(
                        title: "Radius",
                        value: $settings.maxBlurRadius,
                        range: 0 ... 24
                    )
                    sliderRow(
                        title: "Fade",
                        value: $settings.fadeExtension,
                        range: 0 ... 180,
                        format: "%.0f"
                    )
                    sliderRow(
                        title: "Top Tint",
                        value: $settings.tintOpacityTop,
                        range: 0 ... 1
                    )
                    sliderRow(
                        title: "Mid Tint",
                        value: $settings.tintOpacityMiddle,
                        range: 0 ... 1
                    )
                }
                .padding(UIConstants.Spacing.medium)
                .frame(width: 300)
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
                Label(isExpanded ? "Hide Blur" : "Tune Blur", systemImage: "slider.horizontal.3")
                    .font(.system(.subheadline, weight: .semibold))
                    .padding(.horizontal, UIConstants.Spacing.medium)
                    .padding(.vertical, UIConstants.Spacing.small)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String = "%.2f"
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(String(format: format, value.wrappedValue))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: range)
        }
    }
}

private struct ProgressiveBlurHeaderLabSettings: Equatable {
    var maxBlurRadius: Double = 7
    var fadeExtension: Double = 88
    var tintOpacityTop: Double = 0.72
    var tintOpacityMiddle: Double = 0.46

    static let `default` = ProgressiveBlurHeaderLabSettings()
}

private struct ProgressiveBlurHeaderDemoRowData {
    let title: String
    let subtitle: String
    let accent: Color
}

private extension Double {
    var cgFloat: CGFloat { CGFloat(self) }
}
