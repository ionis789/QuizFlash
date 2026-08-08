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
            compactStatusContent
                .padding(.horizontal, UIConstants.Spacing.standard)
                .frame(minWidth: UIConstants.Size.capsuleHeight)
                .frame(height: UIConstants.Size.capsuleHeight)
                .background(
                    themeManager.roleColor(.buttonSurfaceFill),
                    in: Capsule(style: .continuous)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(FloatingAIWorkspaceButtonStyle())
        .accessibilityLabel(localized("Open AI workspace"))
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var compactStatusContent: some View {
        switch status.phase {
        case .preparing:
            ProgressActivityDots(color: tint)
                .frame(width: UIConstants.Size.iconStandard)
        case .running, .paused:
            Text(progressCardsText)
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(tint)
                .fixedSize(horizontal: true, vertical: false)
                .statusTextMotion(trigger: progressCardsText)
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
        case .failed:
            Image(systemName: "exclamationmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
        }
    }

    private var progressCardsText: String {
        let progress = status.progressLabel ?? "0/0"
        let format = AppLocalization.string("%@ cards", locale: appPreferences.resolvedLocale)
        return String(format: format, locale: appPreferences.resolvedLocale, progress)
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

    private var accessibilityValue: String {
        [phaseTitle, status.progressLabel, status.subtitle]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
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
