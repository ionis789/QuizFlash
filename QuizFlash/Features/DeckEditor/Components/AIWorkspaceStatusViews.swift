//
//  AIWorkspaceStatusViews.swift
//  QuizFlash
//
//  Floating status, failure, and runtime surfaces for the AI workspace.
//

import SwiftData
import SwiftUI

// MARK: - Floating Status

struct FloatingAIWorkspaceStatusMenu: View {
    let status: AIWorkspaceFloatingStatus
    var bottomPadding: CGFloat
    let onOpenWorkspace: () -> Void
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    private var accent: Color {
        themeManager.accentColor.color
    }

    private var tint: Color {
        switch status.phase {
        case .failed:
            return .red
        case .completed:
            return .green
        case .paused:
            return .orange
        case .preparing, .running:
            return accent
        }
    }

    var body: some View {
        workspaceButton
            .padding(.trailing, UIConstants.Layout.compactScreenEdgeInset)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .transition(.scale(scale: 0.92, anchor: .trailing).combined(with: .opacity))
    }

    private var workspaceButton: some View {
        Button(action: onOpenWorkspace) {
            statusContent
                .padding(.horizontal, UIConstants.Spacing.medium)
                .frame(
                    width: UIConstants.Size.floatingAIStatusWidth,
                    height: UIConstants.Size.floatingAIStatusHeight
                )
                .background {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule(style: .continuous)
                                .fill(themeManager.roleColor(.buttonSurfaceFill).opacity(0.82))
                        }
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.09), lineWidth: 0.75)
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(FloatingAIWorkspaceButtonStyle())
        .accessibilityLabel(localized("Open AI workspace"))
        .accessibilityValue(accessibilityValue)
    }

    private var statusContent: some View {
        HStack(spacing: UIConstants.Spacing.medium) {
            FloatingAIWorkspaceStatusIndicator(
                progress: status.progressFraction,
                tint: tint,
                systemImage: status.systemImage
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: UIConstants.Spacing.small) {
                    Text(phaseTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if let progressLabel = status.progressLabel,
                       status.phase == .preparing || status.phase == .running || status.phase == .paused {
                        Text(progressLabel)
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(tint)
                            .statusTextMotion(trigger: progressLabel)
                    }
                }

                if let subtitle = displaySubtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.tertiary)
        }
    }

    private var phaseTitle: String {
        switch status.phase {
        case .preparing:
            return localized("Preparing request")
        case .running:
            return localized("Generating cards")
        case .paused:
            return localized("Paused")
        case .completed:
            return localized("Done")
        case .failed:
            return localized("Generation stopped")
        }
    }

    private var displaySubtitle: String? {
        let subtitle = status.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !subtitle.isEmpty {
            return subtitle
        }
        if status.phase == .preparing {
            return localized("Preparing source")
        }
        return nil
    }

    private var accessibilityValue: String {
        [phaseTitle, status.progressLabel, displaySubtitle]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: appPreferences.resolvedLocale)
    }
}

private struct FloatingAIWorkspaceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.92 : 1)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(
                .easeInOut(duration: UIConstants.Animation.instant),
                value: configuration.isPressed
            )
    }
}

private struct FloatingAIWorkspaceStatusIndicator: View {
    let progress: Double?
    let tint: Color
    let systemImage: String

    var body: some View {
        if let progress {
            AnimatedProgressRing(
                progress: progress,
                trackColor: tint.opacity(0.18),
                progressColor: tint,
                size: UIConstants.Size.iconLarge,
                strokeWidth: 3
            ) { _ in
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
            }
        } else {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))

                if systemImage == "doc.text.viewfinder" {
                    ProgressActivityDots(color: tint)
                        .scaleEffect(0.72)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: UIConstants.Size.iconLarge, height: UIConstants.Size.iconLarge)
        }
    }
}

struct AIWorkspaceFailureCard: View {
    let title: String
    let message: String
    let tint: Color
    var onRetry: (() -> Void)? = nil
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            HStack(spacing: UIConstants.Spacing.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: UIConstants.Spacing.small) {
                if let onRetry {
                    Button("Resume", action: onRetry)
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(tint, in: Capsule())
                        .foregroundStyle(.white)
                }

                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                    .foregroundStyle(.primary)
            }
            .font(.system(size: 14, weight: .bold))
        }
        .padding(UIConstants.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        }
    }
}

// MARK: - Runtime Card

struct AIWorkspaceRuntimeCard: View {
    @Environment(ThemeManager.self) private var themeManager

    @Bindable var coordinator: AIWorkspaceCoordinator
    var onOpenDestinationDeck: ((PersistentIdentifier) -> Void)? = nil

    private var accent: Color {
        themeManager.accentColor.color
    }

    var body: some View {
        EmptyView()
    }
}
