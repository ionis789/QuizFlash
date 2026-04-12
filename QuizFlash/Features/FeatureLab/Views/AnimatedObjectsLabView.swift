//
//  AnimatedObjectsLabView.swift
//  QuizFlash
//
//  Dedicated lab for standalone animated UI objects before production wiring.
//

import Observation
import SwiftUI

struct AnimatedObjectsLabView: View {
    @State private var state = AnimatedObjectsLabState()

    var body: some View {
        @Bindable var state = state

        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: UIConstants.Layout.sectionSpacing) {
                LargeScreenTitle(title: "Animated Objects Lab")

                SettingsInfoCard(
                    icon: "sparkles.rectangle.stack.fill",
                    tint: .cyan,
                    text: "Use this lab to tune standalone motion objects before wiring them into swipe flows. The first object is the swipe arrow Lottie and exposes phase, progress, playback timing, size, and exit timing."
                )

                SettingsSectionCard(
                    title: "Swipe Arrow",
                    subtitle: "Standalone controller for the swipe arrow object used by the flashcards swipe sandbox."
                ) {
                    previewStage

                    SettingsCardDivider()

                    VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
                        segmentedPickerRow(
                            title: "Phase",
                            selection: $state.phase,
                            options: SwipeArrowAnimatedObjectPhase.allCases
                        ) { $0.title }

                        segmentedPickerRow(
                            title: "Direction",
                            selection: $state.direction,
                            options: SwipeArrowDirectionSelection.allCases
                        ) { $0.title }

                        Toggle(isOn: $state.fastSwipeDetected) {
                            panelLabel("Fast Commit")
                        }
                        .tint(.cyan)

                        actionRow

                        sliderRow(
                            title: "Visual Progress",
                            value: $state.displayProgress,
                            range: 0...1,
                            tint: .cyan
                        )

                        sliderRow(
                            title: "Exit Progress",
                            value: $state.dismissFlightProgress,
                            range: 0...1,
                            tint: .orange
                        )

                        sliderRow(
                            title: "Object Width",
                            value: $state.tuning.baseWidth,
                            range: 16...64,
                            tint: .green
                        )

                        sliderRow(
                            title: "Dead Zone",
                            value: $state.tuning.deadZone,
                            range: 0...0.35,
                            tint: .purple
                        )

                        sliderRow(
                            title: "Display Curve",
                            value: $state.tuning.displayCurve,
                            range: 0.35...1.8,
                            tint: .purple
                        )

                        sliderRow(
                            title: "Commit End",
                            value: $state.tuning.commitEndProgress,
                            range: 0.15...1,
                            tint: .mint
                        )

                        sliderRow(
                            title: "Commit Duration",
                            value: $state.tuning.commitDuration,
                            range: 0.08...0.8,
                            tint: .orange
                        )

                        sliderRow(
                            title: "Fast Duration",
                            value: $state.tuning.fastCommitDuration,
                            range: 0.06...0.5,
                            tint: .red
                        )

                        sliderRow(
                            title: "Min Speed",
                            value: $state.tuning.minimumCommitSpeed,
                            range: 0.5...8,
                            tint: .indigo
                        )
                    }
                }
            }
            .padding(.horizontal, UIConstants.Spacing.large)
            .padding(.top, UIConstants.Spacing.large)
            .padding(.bottom, UIConstants.Size.bottomChromeBarHeight + 120)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Animated Objects")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var previewStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)

            stageGuides

            SwipeArrowAnimatedObjectView(
                presentation: state.presentation,
                isCompact: true,
                tuning: state.normalizedTuning
            )
            .padding(.horizontal, UIConstants.Spacing.large)
        }
        .frame(height: 220)
    }

    private var stageGuides: some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 1)

            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)
        }
        .padding(.horizontal, UIConstants.Spacing.large)
        .padding(.vertical, UIConstants.Spacing.large)
    }

    private var actionRow: some View {
        HStack(spacing: UIConstants.Spacing.small) {
            actionButton(title: "Track", tint: .cyan) {
                state.activateTracking()
            }

            actionButton(title: "Commit", tint: .green) {
                state.triggerCommit(fast: false)
            }

            actionButton(title: "Fast", tint: .orange) {
                state.triggerCommit(fast: true)
            }

            actionButton(title: "Exit", tint: .pink) {
                state.activateExit()
            }

            actionButton(title: "Reset", tint: .white, isNeutral: true) {
                state.reset()
            }
        }
    }

    private func actionButton(
        title: String,
        tint: Color,
        isNeutral: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(isNeutral ? Color.primary : tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill((isNeutral ? Color.white : tint).opacity(isNeutral ? 0.08 : 0.16))
                )
        }
        .buttonStyle(.plain)
    }

    private func segmentedPickerRow<Option: Identifiable & Hashable>(
        title: String,
        selection: Binding<Option>,
        options: [Option],
        titleForOption: @escaping (Option) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            panelLabel(title)

            Picker(title, selection: selection) {
                ForEach(options) { option in
                    Text(titleForOption(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func sliderRow(
        title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                Spacer(minLength: 0)

                Text(Double(value.wrappedValue).formatted(.number.precision(.fractionLength(2))))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: range)
                .tint(tint)
        }
    }

    private func panelLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(.primary)
            .textCase(.uppercase)
    }
}

// MARK: - Animated Objects Lab State

@MainActor
@Observable
private final class AnimatedObjectsLabState {
    var phase: SwipeArrowAnimatedObjectPhase = .tracking
    var direction: SwipeArrowDirectionSelection = .right
    var displayProgress: CGFloat = 0.34
    var dismissFlightProgress: CGFloat = 0.42
    var fastSwipeDetected = false
    var commitToken = 0
    var tuning = SwipeArrowAnimatedObjectTuning()

    var presentation: SwipeArrowAnimatedObjectPresentation {
        switch phase {
        case .idle:
            return .idle
        case .tracking:
            return SwipeArrowAnimatedObjectPresentation(
                phase: .tracking,
                direction: direction.swipeDirection,
                displayProgress: displayProgress,
                commitToken: commitToken
            )
        case .commit:
            return SwipeArrowAnimatedObjectPresentation(
                phase: .commit,
                direction: direction.swipeDirection,
                displayProgress: displayProgress,
                commitToken: commitToken,
                fastSwipeDetected: fastSwipeDetected
            )
        case .exit:
            return SwipeArrowAnimatedObjectPresentation(
                phase: .exit,
                direction: direction.swipeDirection,
                displayProgress: displayProgress,
                dismissFlightProgress: dismissFlightProgress,
                commitToken: commitToken,
                fastSwipeDetected: fastSwipeDetected
            )
        }
    }

    var normalizedTuning: SwipeArrowAnimatedObjectTuning {
        var normalized = tuning
        normalized.commitEndProgress = min(max(normalized.commitEndProgress, 0.25), 1)
        normalized.fastCommitDuration = min(normalized.fastCommitDuration, normalized.commitDuration)
        normalized.minimumCommitSpeed = max(normalized.minimumCommitSpeed, 0.1)
        return normalized
    }

    init() {
        tuning.baseWidth = 28
        tuning.commitEndProgress = 1
        tuning.commitDuration = 0.62
        tuning.fastCommitDuration = 0.46
        tuning.minimumCommitSpeed = 1
    }

    func activateTracking() {
        phase = .tracking
        dismissFlightProgress = 0
        displayProgress = max(displayProgress, 0.08)
    }

    func triggerCommit(fast: Bool) {
        fastSwipeDetected = fast
        phase = .commit
        dismissFlightProgress = 0
        displayProgress = 1
        commitToken += 1
    }

    func activateExit() {
        phase = .exit
        displayProgress = 1
        dismissFlightProgress = max(dismissFlightProgress, 0.52)
    }

    func reset() {
        phase = .tracking
        direction = .right
        displayProgress = 0.34
        dismissFlightProgress = 0.42
        fastSwipeDetected = false
        commitToken = 0
        tuning = SwipeArrowAnimatedObjectTuning()
        tuning.baseWidth = 28
        tuning.commitEndProgress = 1
        tuning.commitDuration = 0.62
        tuning.fastCommitDuration = 0.46
        tuning.minimumCommitSpeed = 1
    }
}

// MARK: - Swipe Arrow Direction Selection

/// Lab-friendly directional picker for the swipe arrow object.
private enum SwipeArrowDirectionSelection: String, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var swipeDirection: SwipeDirection {
        switch self {
        case .left:
            .left
        case .right:
            .right
        }
    }
}
