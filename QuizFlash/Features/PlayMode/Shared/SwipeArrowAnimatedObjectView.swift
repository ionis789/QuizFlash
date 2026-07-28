//
//  SwipeArrowAnimatedObjectView.swift
//  QuizFlash
//
//  Shared swipe arrow object backed by the local Lottie resource.
//

import Lottie
import SwiftUI
import UIKit

private enum SwipeArrowDirectionPalette {
    static var leftColor: Color { ThemeManager.shared.dangerPrimary }
    static var rightColor: Color { ThemeManager.shared.successPrimary }

    static func uiColor(for direction: SwipeDirection?) -> UIColor {
        switch direction {
        case .left:
            UIColor(leftColor)
        case .right, nil:
            UIColor(rightColor)
        }
    }

    static func color(for direction: SwipeDirection?) -> Color {
        switch direction {
        case .left:
            leftColor
        case .right, nil:
            rightColor
        }
    }
}

// MARK: - Swipe Arrow Animated Object Phase

/// Playback phase for the standalone swipe arrow object.
enum SwipeArrowAnimatedObjectPhase: String, CaseIterable, Identifiable {
    case idle
    case tracking
    case commit
    case exit

    var id: String { rawValue }

    /// Short diagnostic title for the playback phase.
    var title: String {
        switch self {
        case .idle:
            return "Idle"
        case .tracking:
            return "Tracking"
        case .commit:
            return "Commit"
        case .exit:
            return "Exit"
        }
    }
}

// MARK: - Swipe Arrow Animated Object Presentation

/// Render payload that drives the visual state of the swipe arrow object.
struct SwipeArrowAnimatedObjectPresentation: Equatable {
    var phase: SwipeArrowAnimatedObjectPhase = .idle
    var direction: SwipeDirection?
    var displayProgress: CGFloat = 0
    var commitStartProgress: CGFloat = 0
    var dismissFlightProgress: CGFloat = 0
    var displacementX: CGFloat = 0
    var commitToken = 0
    var fastSwipeDetected = false

    static let idle = SwipeArrowAnimatedObjectPresentation()
}

// MARK: - Swipe Arrow Animated Object Tuning

/// Tunable motion and playback values for the swipe arrow object.
struct SwipeArrowAnimatedObjectTuning: Equatable {
    var deadZone: CGFloat = 0.12
    var displayCurve: CGFloat = 0.82
    var baseWidth: CGFloat = 28
    var commitEndProgress: CGFloat = 1
    var commitDuration: CGFloat = 0.62
    var fastCommitDuration: CGFloat = 0.46
    var minimumCommitSpeed: CGFloat = 1
}

// MARK: - Swipe Arrow Animation Resource

/// Local loader for the swipe arrow Lottie resource.
enum SwipeArrowAnimationResource {
    static let name = "swipe_arrow"

    static let animation: LottieAnimation? = {
        if let animation = LottieAnimation.named(
            name,
            bundle: .main,
            subdirectory: "Features/PlayMode/Shared/Resources/Lottie"
        ) {
            return animation
        }

        if let animation = LottieAnimation.named(name, bundle: .main) {
            return animation
        }

        guard let url = resolvedURL(in: .main) else { return nil }
        return LottieAnimation.filepath(url.path)
    }()

    private static func resolvedURL(in bundle: Bundle) -> URL? {
        let exactName = "\(name).json"

        let directCandidates: [URL?] = [
            bundle.url(forResource: name, withExtension: "json"),
            bundle.url(
                forResource: name,
                withExtension: "json",
                subdirectory: "Features/PlayMode/Shared/Resources/Lottie"
            ),
            bundle.url(
                forResource: name,
                withExtension: "json",
                subdirectory: "PlayMode/Shared/Resources/Lottie"
            )
        ]

        if let exactMatch = directCandidates.compactMap(\.self).first {
            return exactMatch
        }

        guard let resourceURL = bundle.resourceURL,
              let enumerator = FileManager.default.enumerator(
                at: resourceURL,
                includingPropertiesForKeys: nil
              )
        else {
            return nil
        }

        for case let candidateURL as URL in enumerator {
            if candidateURL.lastPathComponent == exactName {
                return candidateURL
            }
        }

        return nil
    }
}

// MARK: - Swipe Arrow Animated Object View

/// Shared visual object used for swipe-arrow motion in Play Mode.
struct SwipeArrowAnimatedObjectView: View {
    let presentation: SwipeArrowAnimatedObjectPresentation
    let isCompact: Bool
    var tuning = SwipeArrowAnimatedObjectTuning()

    var body: some View {
        if direction != nil {
            ZStack {
                if SwipeArrowAnimationResource.animation != nil {
                    SwipeArrowAnimatedObjectLottieView(
                        presentation: presentation,
                        tuning: tuning
                    )
                } else {
                    fallbackGlyph
                }
            }
            .padding(.horizontal, tuning.baseWidth * 0.02)
            .frame(width: tuning.baseWidth, height: tuning.baseWidth * 0.44)
            .rotationEffect(.degrees(rotationAngle))
            .scaleEffect(scale)
            .opacity(opacity)
            .shadow(
                color: shadowColor.opacity(shadowOpacity),
                radius: shadowRadius,
                x: 0,
                y: shadowYOffset
            )
            .padding(.horizontal, horizontalEdgeInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: containerAlignment)
            .accessibilityHidden(true)
        }
    }

    private var direction: SwipeDirection? {
        presentation.direction
    }

    private var visualProgress: CGFloat {
        resolvedVisualProgress(from: presentation.displayProgress)
    }

    private var commitEngageProgress: CGFloat {
        guard presentation.phase == .commit else { return 1 }

        let denominator = max(1 - presentation.commitStartProgress, 0.001)
        let normalizedProgress = (presentation.displayProgress - presentation.commitStartProgress) / denominator
        return resolvedEaseOut(normalizedProgress)
    }

    private var exitFadeProgress: CGFloat {
        let fadeStart: CGFloat = 0.76
        let rawProgress = min(max(presentation.dismissFlightProgress, 0), 1)
        guard rawProgress > fadeStart else { return 0 }

        return (rawProgress - fadeStart) / max(1 - fadeStart, 0.001)
    }

    private var rotationAngle: Double {
        switch direction {
        case .left:
            180
        case .right:
            0
        case nil:
            0
        }
    }

    private var containerAlignment: Alignment {
        switch direction {
        case .left:
            .leading
        case .right:
            .trailing
        case nil:
            .center
        }
    }

    private var horizontalEdgeInset: CGFloat {
        isCompact ? 50 : 50
    }

    private var scale: CGFloat {
        let trackingScale = 0.06 + (visualProgress * 0.14)
        let fastBoost: CGFloat = presentation.fastSwipeDetected ? 0.015 : 0

        return switch presentation.phase {
        case .idle:
            0.04
        case .tracking:
            trackingScale
        case .commit:
            max(0.16, trackingScale) + (0.04 * commitEngageProgress) + fastBoost
        case .exit:
            0.20 - (0.03 * resolvedEaseOut(exitFadeProgress))
        }
    }

    private var opacity: Double {
        let trackingOpacity = min(1, 0.08 + (visualProgress * 0.92))

        return switch presentation.phase {
        case .idle:
            0
        case .tracking:
            Double(trackingOpacity)
        case .commit:
            1
        case .exit:
            Double(max(0, 1 - pow(exitFadeProgress, 1.12)))
        }
    }

    private var shadowColor: Color {
        SwipeArrowDirectionPalette.color(for: direction)
    }

    private var shadowOpacity: Double {
        switch presentation.phase {
        case .idle:
            0
        case .tracking:
            Double(0.02 + (visualProgress * 0.04))
        case .commit:
            0.08
        case .exit:
            Double(0.05 * (1 - exitFadeProgress))
        }
    }

    private var shadowRadius: CGFloat {
        switch presentation.phase {
        case .idle:
            0
        case .tracking:
            isCompact ? 5 : 7
        case .commit:
            isCompact ? 7 : 9
        case .exit:
            isCompact ? 6 : 8
        }
    }

    private var shadowYOffset: CGFloat {
        switch presentation.phase {
        case .idle:
            0
        case .tracking:
            2
        case .commit:
            3
        case .exit:
            2
        }
    }

    private var fallbackGlyph: some View {
        Image(systemName: "chevron.forward.2")
            .font(.system(size: tuning.baseWidth * 0.30, weight: .black))
            .foregroundStyle(shadowColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resolvedVisualProgress(from rawProgress: CGFloat) -> CGFloat {
        let clampedProgress = min(max(rawProgress, 0), 1)
        guard clampedProgress > tuning.deadZone else { return 0 }

        let normalized = (clampedProgress - tuning.deadZone) / max(1 - tuning.deadZone, 0.001)
        return pow(min(max(normalized, 0), 1), tuning.displayCurve)
    }

    private func resolvedEaseOut(_ progress: CGFloat) -> CGFloat {
        let clampedProgress = min(max(progress, 0), 1)
        return 1 - pow(1 - clampedProgress, 1.55)
    }
}

// MARK: - Swipe Arrow Animated Object Lottie View

/// UIKit bridge that scrubs during tracking and plays a full segment during commit.
private struct SwipeArrowAnimatedObjectLottieView: UIViewRepresentable {
    let presentation: SwipeArrowAnimatedObjectPresentation
    let tuning: SwipeArrowAnimatedObjectTuning

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView(animation: SwipeArrowAnimationResource.animation)
        view.backgroundBehavior = .pauseAndRestore
        view.contentMode = .scaleAspectFit
        view.currentProgress = 0
        view.animationSpeed = 1
        return view
    }

    func updateUIView(_ view: LottieAnimationView, context: Context) {
        context.coordinator.update(
            view,
            presentation: presentation,
            tuning: tuning
        )
    }

    final class Coordinator {
        private let strokeColorKeypath = AnimationKeypath(keypath: "**.Stroke 1.Color")
        private var lastCommitToken = -1
        private var lastPhase: SwipeArrowAnimatedObjectPhase = .idle
        private var lastDirection: SwipeDirection?

        func update(
            _ view: LottieAnimationView,
            presentation: SwipeArrowAnimatedObjectPresentation,
            tuning: SwipeArrowAnimatedObjectTuning
        ) {
            applyDirectionColorIfNeeded(on: view, direction: presentation.direction)

            switch presentation.phase {
            case .idle:
                if view.isAnimationPlaying {
                    view.stop()
                }
                if abs(view.currentProgress) > 0.001 {
                    view.currentProgress = 0
                }
            case .tracking:
                if view.isAnimationPlaying {
                    view.stop()
                }
                if abs(view.currentProgress) > 0.001 {
                    view.currentProgress = 0
                }
            case .commit:
                triggerCommitPlaybackIfNeeded(
                    on: view,
                    presentation: presentation,
                    tuning: tuning
                )
            case .exit:
                if presentation.commitToken != lastCommitToken {
                    triggerCommitPlaybackIfNeeded(
                        on: view,
                        presentation: presentation,
                        tuning: tuning
                    )
                }
            }

            lastPhase = presentation.phase
        }

        private func applyDirectionColorIfNeeded(
            on view: LottieAnimationView,
            direction: SwipeDirection?
        ) {
            guard direction != lastDirection else { return }

            let uiColor = SwipeArrowDirectionPalette.uiColor(for: direction)

            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

            let provider = ColorValueProvider(
                LottieColor(
                    r: Double(red),
                    g: Double(green),
                    b: Double(blue),
                    a: Double(alpha)
                )
            )

            view.setValueProvider(provider, keypath: strokeColorKeypath)
            lastDirection = direction
        }

        private func triggerCommitPlaybackIfNeeded(
            on view: LottieAnimationView,
            presentation: SwipeArrowAnimatedObjectPresentation,
            tuning: SwipeArrowAnimatedObjectTuning
        ) {
            let targetCommitEnd = min(max(tuning.commitEndProgress, 0.25), 1)

            guard presentation.commitToken != lastCommitToken
                || (!view.isAnimationPlaying && view.currentProgress < targetCommitEnd - 0.01)
                else {
                return
            }

            let startProgress: CGFloat = 0
            let segmentProgress = max(targetCommitEnd - startProgress, 0.12)
            let animationDuration = view.animation?.duration ?? 2.24
            let desiredDuration = max(
                presentation.fastSwipeDetected ? tuning.fastCommitDuration : tuning.commitDuration,
                0.12
            )
            let playbackSpeed = max(
                tuning.minimumCommitSpeed,
                CGFloat((animationDuration * Double(segmentProgress)) / Double(desiredDuration))
            )

            view.stop()
            view.currentProgress = startProgress
            view.animationSpeed = playbackSpeed
            view.play(
                fromProgress: startProgress,
                toProgress: targetCommitEnd,
                loopMode: .playOnce,
                completion: nil
            )

            lastCommitToken = presentation.commitToken
        }
    }
}
