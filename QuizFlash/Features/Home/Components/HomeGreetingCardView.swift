//
//  HomeGreetingCardView.swift
//  QuizFlash
//
//  Resume-oriented greeting widget shown at the top of Home.
//

import SwiftUI

// MARK: - Home Greeting Card

struct HomeGreetingCardView: View {

    let summary: HomeGreetingSummary
    let availableWidth: CGFloat
    let onPrimaryAction: (() -> Void)?

    private var tintColor: Color {
        Color(hex: summary.colorHex) ?? ThemeManager.shared.accentColor.color
    }

    private var layout: HomeGreetingCardLayout {
        HomeGreetingCardLayout(
            kind: availableWidth >= 620 ? .pad : .phone,
            availableWidth: availableWidth
        )
    }

    var body: some View {
        Group {
            if availableWidth >= 980 {
                padLayout
            } else if availableWidth >= 680 {
                wideLayout
            } else if layout.kind == .pad {
                compactLayout
            } else if layout.usesWideLayout {
                wideLayout
            } else {
                compactLayout
            }
        }
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, minHeight: layout.minHeight, alignment: .leading)
        .widgetStyle(cornerRadius: 30)
    }

    private var padLayout: some View {
        VStack(alignment: .leading, spacing: 18) {
            headingBlock(titleSize: layout.titleSize)

            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    contextRow(iconSize: layout.iconBoxSize, titleLineLimit: 2)
                    pillRow
                }
                .frame(maxWidth: layout.leadingColumnWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 16) {
                    progressRing(size: layout.ringSize)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    if let ctaTitle = summary.ctaTitle, let onPrimaryAction {
                        Button(action: onPrimaryAction) {
                            Text(ctaTitle)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                                .frame(width: layout.padButtonWidth)
                                .frame(height: UIConstants.Size.buttonHeight)
                                .glassButton(shape: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: layout.trailingColumnWidth, alignment: .trailing)
            }
        }
    }

    private var wideLayout: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 18) {
                headingBlock(titleSize: layout.titleSize)
                contextRow(iconSize: layout.iconBoxSize, titleLineLimit: 2)
                pillRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 16) {
                progressRing(size: layout.ringSize)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                if let ctaTitle = summary.ctaTitle, let onPrimaryAction {
                    Button(action: onPrimaryAction) {
                        Text(ctaTitle)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 18)
                            .frame(height: UIConstants.Size.buttonHeight)
                            .glassButton(shape: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: layout.trailingColumnWidth, alignment: .trailing)
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                headingBlock(titleSize: layout.titleSize)
                    .frame(maxWidth: .infinity, alignment: .leading)

                progressRing(size: layout.ringSize)
            }

            contextRow(iconSize: layout.iconBoxSize, titleLineLimit: 2)

            pillRow

            if let ctaTitle = summary.ctaTitle, let onPrimaryAction {
                Button(action: onPrimaryAction) {
                    Text(ctaTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: UIConstants.Size.buttonHeight)
                        .glassButton(shape: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func headingBlock(titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary.title)
                .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(summary.subtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func contextRow(iconSize: CGFloat, titleLineLimit: Int) -> some View {
        HStack(alignment: .center, spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tintColor.opacity(0.14))
                .frame(width: iconSize, height: iconSize)
                .overlay {
                    Image(systemName: summary.icon)
                        .font(.system(size: iconSize * 0.4, weight: .semibold))
                        .foregroundStyle(tintColor)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.contextTitle)
                    .font(.system(size: layout.contextTitleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(titleLineLimit)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: false, vertical: true)

                Text(summary.contextLine)
                    .font(.system(size: layout.contextBodySize, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(layout.kind == .pad ? 3 : nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pillRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                HomeGreetingPill(text: summary.primaryPill, tint: tintColor)

                if let secondaryPill = summary.secondaryPill {
                    HomeGreetingPill(text: secondaryPill, tint: .secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HomeGreetingPill(text: summary.primaryPill, tint: tintColor)

                if let secondaryPill = summary.secondaryPill {
                    HomeGreetingPill(text: secondaryPill, tint: .secondary)
                }
            }
        }
    }

    private func progressRing(size: CGFloat) -> some View {
        AnimatedProgressRing(
            progress: summary.progressFraction,
            trackColor: Color.primary.opacity(0.10),
            progressColor: tintColor,
            size: size,
            strokeWidth: max(8, size * 0.11)
        ) { _ in
            VStack(spacing: 2) {
                Text(summary.progressValueText)
                    .font(.system(size: size * 0.24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(summary.progressLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Greeting Layout

private struct HomeGreetingCardLayout {
    enum Kind {
        case phone
        case pad
    }

    let kind: Kind
    let availableWidth: CGFloat

    var usesWideLayout: Bool {
        switch kind {
        case .phone:
            return availableWidth >= 560
        case .pad:
            return availableWidth >= 860
        }
    }

    var contentPadding: CGFloat {
        kind == .pad ? 22 : 20
    }

    var minHeight: CGFloat {
        switch kind {
        case .pad:
            return usesWideLayout ? 184 : 236
        case .phone:
            return usesWideLayout ? 188 : 240
        }
    }

    var titleSize: CGFloat {
        kind == .pad ? 28 : 28
    }

    var contextTitleSize: CGFloat {
        kind == .pad ? 18 : 18
    }

    var contextBodySize: CGFloat {
        kind == .pad ? 15 : 16
    }

    var iconBoxSize: CGFloat {
        kind == .pad ? 58 : 56
    }

    var ringSize: CGFloat {
        kind == .pad ? 86 : 84
    }

    var trailingColumnWidth: CGFloat {
        kind == .pad
            ? max(192, min(availableWidth * 0.20, 220))
            : max(ringSize + 28, availableWidth * 0.24)
    }

    var padButtonWidth: CGFloat {
        min(max(184, availableWidth * 0.16), trailingColumnWidth)
    }

    var leadingColumnWidth: CGFloat {
        kind == .pad
            ? min(max(availableWidth * 0.50, 420), 560)
            : availableWidth
    }
}

// MARK: - Greeting Pill

private struct HomeGreetingPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(Color.primary.opacity(0.06))
            }
    }
}
