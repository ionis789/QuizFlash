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
    var onOpenWorkspace: (() -> Void)? = nil
    var onPauseResume: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
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
        FloatingAIWorkspaceCapsuleContainer {
            HStack(spacing: UIConstants.Spacing.small) {
                if let onOpenWorkspace {
                    Button(action: onOpenWorkspace) {
                        compactContent
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open AI workspace")
                } else {
                    compactContent
                }

                if let onPauseResume {
                    Button(action: onPauseResume) {
                        Image(systemName: pauseResumeSymbol)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(tint)
                            .frame(width: 24, height: 24)
                            .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(status.phase == .paused ? "Resume AI workspace job" : "Pause AI workspace job")
                }

                if let onCancel {
                    Button(action: onCancel) {
                        ChromeSoftCircleSymbol(
                            systemName: "xmark",
                            size: 22,
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel AI workspace job")
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var compactContent: some View {
        HStack(spacing: UIConstants.Spacing.small) {
            FloatingAIWorkspaceStatusIndicator(
                countText: compactCountText,
                tint: tint,
                fallbackSystemImage: status.systemImage
            )

            if compactCountText == nil {
                Text(compactTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
    }

    private var compactTitle: String {
        switch status.phase {
        case .completed:
            return "Done"
        case .failed:
            return "Error"
        case .preparing, .running, .paused:
            return "Generate"
        }
    }

    private var compactCountText: String? {
        if status.phase == .preparing || status.phase == .running || status.phase == .paused,
           let progressLabel = status.progressLabel {
            return progressLabel
        }
        return nil
    }

    private var pauseResumeSymbol: String {
        status.phase == .paused ? "play.fill" : "pause.fill"
    }
}

private struct FloatingAIWorkspaceCapsuleContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, UIConstants.Spacing.standard)
            .frame(minWidth: UIConstants.Size.capsuleHeight)
            .frame(height: UIConstants.Size.capsuleHeight)
    }
}

private struct FloatingAIWorkspaceStatusIndicator: View {
    let countText: String?
    let tint: Color
    let fallbackSystemImage: String

    var body: some View {
        if let countText {
            VStack(spacing: 2) {
                Text(countText)
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .statusTextMotion(trigger: countText)

                ProgressActivityDots(color: tint)
                    .frame(minWidth: 22)
            }
            .fixedSize(horizontal: true, vertical: false)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: countText)
        } else {
            Image(systemName: fallbackSystemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
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
