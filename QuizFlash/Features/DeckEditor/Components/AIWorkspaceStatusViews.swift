//
//  AIWorkspaceStatusViews.swift
//  QuizFlash
//
//  Floating status, failure, and runtime surfaces for the AI workspace.
//

import SwiftUI
import SwiftData

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
            return status.kind == .conversion ? .orange : accent
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
                            .font(.system(size: 11, weight: .bold, design: .rounded))
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
                            symbolSize: 16
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
                    .font(.system(size: 13, weight: .bold, design: .rounded))
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
            return status.kind == .conversion ? "Convert" : "Generate"
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
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .statusTextMotion(trigger: countText)

                AIGenerationActivityDots(color: tint)
                    .frame(minWidth: 22)
            }
            .fixedSize(horizontal: true, vertical: false)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: countText)
        } else {
            Image(systemName: fallbackSystemImage)
                .font(.system(size: 14, weight: .bold, design: .rounded))
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
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
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
            .font(.system(size: 14, weight: .bold, design: .rounded))
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
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var themeManager

    @Bindable var coordinator: AIWorkspaceCoordinator
    var onOpenDestinationDeck: ((PersistentIdentifier) -> Void)? = nil

    private var accent: Color {
        themeManager.accentColor.color
    }

    var body: some View {
        Group {
            if let errorMessage = coordinator.conversionErrorMessage {
                errorCard(errorMessage)
            } else if let progress = coordinator.conversionProgress {
                progressCard(progress)
            } else if let summary = coordinator.conversionSummary {
                summaryCard(summary)
            }
        }
    }

    private func progressCard(_ progress: DeckCardConversionProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conversion")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.45)

            HStack(alignment: .firstTextBaseline, spacing: UIConstants.Spacing.small) {
                Text(coordinator.canResumeConversion ? "Conversion paused" : "Converting cards")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Text("\(progress.completedCount)/\(progress.totalCount)")
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(progress.statusMessage)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: progress.fractionCompleted)
                .tint(.orange)

            HStack(spacing: UIConstants.Spacing.small) {
                runtimeChip("\(progress.createdCount) created", tint: accent)
                runtimeChip("\(progress.skippedCount) skipped", tint: .secondary)
                if progress.failedCount > 0 {
                    runtimeChip("\(progress.failedCount) failed", tint: .red)
                }
            }

            if coordinator.canResumeConversion {
                HStack(spacing: UIConstants.Spacing.small) {
                    Button("Resume") {
                        coordinator.resumeConversion(context: context)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(Color.white.opacity(0.06), in: Capsule())

                    Button("Dismiss") {
                        coordinator.dismissConversionOutcome()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(Color.white.opacity(0.04), in: Capsule())
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
            }
        }
        .padding(18)
        .background(sectionBackground)
    }

    private func summaryCard(_ summary: DeckCardConversionSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conversion")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.45)

            Text(summary.createdCount == 1
                 ? "1 \(summary.targetKind.displayTitle) card created"
                 : "\(summary.createdCount) \(summary.targetKind.displayTitle) cards created")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(summary.destinationDeckTitle)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: UIConstants.Spacing.small) {
                runtimeChip("\(summary.skippedCount) skipped", tint: .secondary)
                if summary.failedCount > 0 {
                    runtimeChip("\(summary.failedCount) failed", tint: .red)
                }
            }

            HStack(spacing: UIConstants.Spacing.small) {
                if let destinationDeckID = summary.destinationDeckID,
                   summary.destination == .newDeck {
                    Button("Open Deck") {
                        onOpenDestinationDeck?(destinationDeckID)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(Color.white.opacity(0.06), in: Capsule())
                }

                Button("Dismiss") {
                    coordinator.dismissConversionOutcome()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Color.white.opacity(0.04), in: Capsule())
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .padding(18)
        .background(sectionBackground)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conversion")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.45)

            Text("Conversion stopped")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: UIConstants.Spacing.small) {
                if coordinator.canResumeConversion {
                    Button("Resume") {
                        coordinator.resumeConversion(context: context)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(Color.white.opacity(0.06), in: Capsule())
                }

                Button("Dismiss") {
                    coordinator.dismissConversionOutcome()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Color.white.opacity(0.04), in: Capsule())
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .padding(18)
        .background(sectionBackground)
    }

    private func runtimeChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.05), in: Capsule())
    }
}
