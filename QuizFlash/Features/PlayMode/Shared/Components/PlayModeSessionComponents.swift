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
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .allowsTightening(true)
                            .frame(maxWidth: titleWidth)

                        Text(subtitle)
                            .font(.system(size: UIConstants.Size.navigationChromeLabel, weight: .bold, design: .rounded))
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
                .font(.system(size: 28, weight: .black, design: .rounded))
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

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool { horizontalSizeClass == .compact }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)

            VStack(spacing: 0) {
                VStack(spacing: UIConstants.Spacing.standard) {
                    ZStack {
                        Circle()
                            .fill(Color.yellow.opacity(0.2))
                            .frame(width: 120, height: 120)

                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: .orange.opacity(0.5), radius: 10, y: 5)
                    }
                    .padding(.bottom, UIConstants.Spacing.small)

                    Text(headline)
                        .font(isCompact ? .title : .largeTitle)
                        .fontWeight(.black)

                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("+\(xpEarned) XP")
                            .fontWeight(.bold)
                    }
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, UIConstants.Spacing.large)
                    .padding(.vertical, UIConstants.Spacing.standard)
                    .background(
                        Capsule().fill(
                            .linearGradient(
                                colors: [.orange, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    )
                    .shadow(color: .orange.opacity(0.3), radius: 8, y: 4)
                }
                .padding(.top, 40)
                .padding(.bottom, UIConstants.Spacing.huge)

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: UIConstants.Spacing.medium
                ) {
                    ForEach(stats) { stat in
                        PlayModeCompletionStatBox(stat: stat)
                    }
                }
                .padding(.horizontal, UIConstants.Spacing.extraLarge)
                .padding(.bottom, UIConstants.Spacing.huge)

                VStack(spacing: UIConstants.Spacing.medium) {
                    Button(primaryActionTitle, action: primaryAction)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, UIConstants.Spacing.standard)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: UIConstants.Radius.card))
                        .foregroundStyle(.white)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 10, y: 5)

                    if let secondaryActionTitle, let secondaryAction {
                        Button(secondaryActionTitle, action: secondaryAction)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, UIConstants.Spacing.standard)
                            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: UIConstants.Radius.card))
                            .foregroundStyle(.orange)
                            .overlay {
                                RoundedRectangle(cornerRadius: UIConstants.Radius.card)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            }
                    }
                }
                .padding(.horizontal, UIConstants.Spacing.extraLarge)
                .padding(.bottom, UIConstants.Spacing.huge)
            }
            .background(
                RoundedRectangle(cornerRadius: UIConstants.Radius.maximum)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.2), radius: 30, y: 15)
            )
            .padding(isCompact ? UIConstants.Spacing.extraLarge : 60)
        }
    }
}

// MARK: - PlayModeCompletionStatBox

/// Shared metric tile displayed inside the session completion overlay.
private struct PlayModeCompletionStatBox: View {
    let stat: PlayModeCompletionStat

    var body: some View {
        HStack(spacing: UIConstants.Spacing.medium) {
            Image(systemName: stat.icon)
                .font(.title2)
                .foregroundStyle(stat.color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(stat.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(stat.value)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(UIConstants.Spacing.standard)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: UIConstants.Radius.card))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}
