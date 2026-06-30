//
//  PlayModeSessionComponents.swift
//  QuizFlash
//
//  Shared session chrome, cards, and completion surfaces for interactive play modes.
//

import SwiftUI

// MARK: - PlayModeSessionHeader

/// Shared top chrome used by immersive play-mode sessions.
struct PlayModeSessionHeader<Leading: View, Trailing: View>: View {
    let deckTitle: String
    let subtitle: String
    let progressLabel: String
    let progressFraction: Double
    let safeTopInset: CGFloat
    let horizontalPadding: CGFloat
    @Binding var measuredHeight: CGFloat
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    @State private var leadingWidth: CGFloat = UIConstants.Size.actionButton
    @State private var trailingWidth: CGFloat = UIConstants.Size.actionButton

    var body: some View {
        VStack(spacing: UIConstants.Spacing.standard) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 56, height: 5)
                .accessibilityHidden(true)

            GeometryReader { proxy in
                let sideClearance = max(leadingWidth, trailingWidth)
                let titleWidth = max(
                    0,
                    proxy.size.width - (sideClearance * 2) - (UIConstants.Spacing.standard * 2)
                )

                ZStack {
                    VStack(spacing: 2) {
                        Text(deckTitle)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .allowsTightening(true)
                            .frame(maxWidth: titleWidth)

                        Text(subtitle)
                            .font(.system(size: UIConstants.Size.navigationChromeLabel, weight: .bold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: UIConstants.Spacing.standard) {
                        leading()
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                proxy.size.width
                            } action: { newWidth in
                                if abs(leadingWidth - newWidth) > 0.5 {
                                    leadingWidth = newWidth
                                }
                            }

                        Spacer(minLength: 0)

                        trailing()
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                proxy.size.width
                            } action: { newWidth in
                                if abs(trailingWidth - newWidth) > 0.5 {
                                    trailingWidth = newWidth
                                }
                            }
                    }
                }
            }
            .frame(height: UIConstants.Size.capsuleHeight)

            PlayModeProgressChrome(
                label: progressLabel,
                fraction: progressFraction
            )
        }
        .padding(.top, safeTopInset + UIConstants.Spacing.tiny)
        .padding(.horizontal, horizontalPadding)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            if abs(measuredHeight - newHeight) > 0.5 {
                measuredHeight = newHeight
            }
        }
    }
}

// MARK: - PlayModeProgressChrome

/// Shared progress bar and summary used inside the session header.
struct PlayModeProgressChrome: View {
    let label: String
    let fraction: Double

    var body: some View {
        VStack(spacing: UIConstants.Spacing.small) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    ThemeManager.shared.accentColor.color.opacity(0.82),
                                    ThemeManager.shared.accentColor.color,
                                    Color.white.opacity(0.92)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: max(
                                0,
                                min(proxy.size.width, proxy.size.width * max(0, min(fraction, 1)))
                            )
                        )
                }
            }
            .frame(height: 6)

            HStack(spacing: UIConstants.Spacing.small) {
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text("\(Int((max(0, min(fraction, 1)) * 100).rounded()))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - PlayModeContentCard

/// Shared widget-style content card used by non-flashcards gameplay surfaces.
struct PlayModeContentCard<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        cornerRadius: CGFloat = UIConstants.Radius.large,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            content()
        }
        .padding(UIConstants.Spacing.large)
        .flashcardStyle(cornerRadius: cornerRadius, surfaceRole: .widget)
    }
}

// MARK: - PlayModeMessageCard

/// Shared empty, invalid, loading, and error state card for play-mode sessions.
struct PlayModeMessageCard: View {
    let icon: String
    let title: String
    let message: String
    let bullets: [String]
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        icon: String,
        title: String,
        message: String,
        bullets: [String] = [],
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.bullets = bullets
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        PlayModeContentCard(cornerRadius: UIConstants.Radius.maximum) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .black))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !bullets.isEmpty {
                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    ForEach(bullets, id: \.self) { bullet in
                        Text("• \(bullet)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(ThemeManager.shared.accentColor.color)
            }
        }
    }
}

// MARK: - PlayModeCompletionOverlay

/// Shared completion overlay used by interactive play modes.
struct PlayModeCompletionOverlay: View {
    let headline: String
    let xpEarned: Int
    let stats: [PlayModeCompletionStat]
    let primaryActionTitle: String
    let primaryAction: () -> Void
    let secondaryActionTitle: String?
    let secondaryAction: (() -> Void)?

    @Environment(ThemeManager.self) private var themeManager

    private var panelCornerRadius: CGFloat { 30 }

    var body: some View {
        GeometryReader { proxy in
            let panelWidth = panelWidth(in: proxy.size.width)

            ZStack {
                themeManager.screenBackground.opacity(0.86)
                    .ignoresSafeArea()

                VStack(spacing: UIConstants.Spacing.large) {
                    completionHeader
                    statsGrid
                    actionButtons
                }
                .padding(.horizontal, UIConstants.Spacing.large)
                .padding(.vertical, UIConstants.Spacing.extraLarge)
                .frame(width: panelWidth)
                .background {
                    RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                        .fill(themeManager.surfacePrimary.opacity(0.34))
                        .overlay {
                            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
    }

    private func panelHorizontalInset(in availableWidth: CGFloat) -> CGFloat {
        min(max(availableWidth * 0.06, 22), 64)
    }

    private func panelWidth(in availableWidth: CGFloat) -> CGFloat {
        let horizontalInset = panelHorizontalInset(in: availableWidth)
        return max(0, availableWidth - (horizontalInset * 2))
    }

    private var completionHeader: some View {
        VStack(spacing: UIConstants.Spacing.small) {
            Text(headline)
                .font(.system(size: 29, weight: .black))
                .foregroundStyle(themeManager.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
    }

    private var statsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: UIConstants.Spacing.small),
                GridItem(.flexible(), spacing: UIConstants.Spacing.small)
            ],
            spacing: UIConstants.Spacing.small
        ) {
            ForEach(stats) { stat in
                PlayModeCompletionStatBox(stat: stat)
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: UIConstants.Spacing.small) {
            completionButton(
                title: primaryActionTitle,
                isPrimary: true,
                action: primaryAction
            )

            if let secondaryActionTitle, let secondaryAction {
                completionButton(
                    title: secondaryActionTitle,
                    isPrimary: false,
                    action: secondaryAction
                )
            }
        }
    }

    private func completionButton(
        title: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(isPrimary ? themeManager.roleColor(.buttonPrimaryForeground) : themeManager.textPrimary)
                .background {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(isPrimary ? themeManager.roleColor(.buttonPrimaryFill) : themeManager.surfaceSecondary.opacity(0.52))
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PlayModeCompletionStatBox

/// Shared metric tile displayed inside the session completion overlay.
private struct PlayModeCompletionStatBox: View {
    let stat: PlayModeCompletionStat

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        VStack(spacing: 4) {
            Text(stat.value)
                .font(.system(size: 31, weight: .black))
                .foregroundStyle(themeManager.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text(stat.title)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(themeManager.textSecondary)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, UIConstants.Spacing.small)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(themeManager.surfaceSecondary.opacity(0.38))
        )
    }
}
