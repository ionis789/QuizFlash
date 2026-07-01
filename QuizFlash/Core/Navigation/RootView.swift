import SwiftUI

// MARK: - Root View

struct RootView: View {

    @Environment(AuthManager.self) var authManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(ThemeManager.self) private var themeManager

    @State private var hasStartedLaunchAnimation = false
    @State private var isLaunchAnimationVisible = true
    @State private var launchPhase: QuizFlashLaunchPhase = .initial

    var body: some View {
        ZStack {
            themeManager.screenBackground
                .ignoresSafeArea()

            Group {
                switch authManager.sessionState {
                case .checking:
                    ProgressActivityDots(color: themeManager.accentColor.color)
                        .transition(.opacity)
                case .signedIn:
                    MainAppView()
                        .transition(.opacity)
                case .signedOut, .emailVerificationRequired, .emailVerificationSucceeded:
                    LoginView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.45), value: authManager.sessionState)

            if isLaunchAnimationVisible {
                QuizFlashLaunchAnimationView(
                    phase: launchPhase
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .task {
            await playLaunchAnimationIfNeeded()
        }
    }

    @MainActor
    private func playLaunchAnimationIfNeeded() async {
        guard !hasStartedLaunchAnimation else { return }
        hasStartedLaunchAnimation = true

        let pulseAnimation: Animation = reduceMotion
            ? .easeOut(duration: 0.16)
            : .spring(response: 0.28, dampingFraction: 0.68)
        let settleAnimation: Animation = reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(response: 0.46, dampingFraction: 0.72)
        let liftAnimation: Animation = reduceMotion
            ? .easeInOut(duration: 0.28)
            : .spring(response: 0.58, dampingFraction: 0.82)
        let exitAnimation: Animation = reduceMotion
            ? .easeInOut(duration: 0.18)
            : .easeInOut(duration: 0.32)

        withAnimation(pulseAnimation) {
            launchPhase = .compressed
        }

        try? await Task.sleep(nanoseconds: reduceMotion ? 140_000_000 : 190_000_000)

        withAnimation(settleAnimation) {
            launchPhase = .settled
        }

        try? await Task.sleep(nanoseconds: reduceMotion ? 300_000_000 : 520_000_000)

        withAnimation(liftAnimation) {
            launchPhase = .lifted
        }

        try? await Task.sleep(nanoseconds: reduceMotion ? 360_000_000 : 660_000_000)

        withAnimation(exitAnimation) {
            launchPhase = .exiting
        }

        try? await Task.sleep(nanoseconds: reduceMotion ? 190_000_000 : 360_000_000)

        isLaunchAnimationVisible = false
    }
}

// MARK: - Launch Animation

private enum QuizFlashLaunchPhase {
    case initial
    case compressed
    case settled
    case lifted
    case exiting
}

private struct QuizFlashLaunchAnimationView: View {

    @Environment(ThemeManager.self) private var themeManager

    let phase: QuizFlashLaunchPhase

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                themeManager.screenBackground
                    .ignoresSafeArea()

                ambientGlow
                    .scaleEffect(glowScale)
                    .offset(y: verticalOffset(in: proxy.size))
                    .opacity(overlayOpacity)

                boltSymbol
                    .scaleEffect(symbolScale)
                    .rotationEffect(.degrees(symbolRotation))
                    .offset(y: verticalOffset(in: proxy.size))
                    .opacity(symbolOpacity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .opacity(containerOpacity)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var ambientGlow: some View {
        RadialGradient(
            colors: [
                launchPurple.opacity(glowCoreOpacity),
                launchPurple.opacity(glowMidOpacity),
                launchPurple.opacity(0.08),
                .clear
            ],
            center: .center,
            startRadius: 8,
            endRadius: glowEndRadius
        )
        .ignoresSafeArea()
    }

    private var boltSymbol: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: 58, weight: .black, design: .rounded))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        .white,
                        Color(red: 0.86, green: 0.82, blue: 1.0),
                        launchPurple
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(
                color: launchPurple.opacity(symbolGlowOpacity),
                radius: symbolGlowRadius
            )
            .shadow(
                color: launchPurple.opacity(phase == .lifted ? 0.50 : 0.18),
                radius: phase == .lifted ? 44 : 18
            )
    }

    private var launchPurple: Color {
        Color(red: 0.62, green: 0.52, blue: 1.0)
    }

    private var symbolScale: CGFloat {
        switch phase {
        case .initial:
            return 1.16
        case .compressed:
            return 0.82
        case .settled:
            return 1.0
        case .lifted:
            return 1.64
        case .exiting:
            return 1.78
        }
    }

    private var symbolRotation: Double {
        switch phase {
        case .initial:
            return -5
        case .compressed:
            return -3
        case .settled, .lifted, .exiting:
            return 0
        }
    }

    private var symbolOpacity: Double {
        switch phase {
        case .initial, .compressed, .settled, .lifted:
            return 1
        case .exiting:
            return 0
        }
    }

    private var containerOpacity: Double {
        switch phase {
        case .initial, .compressed, .settled, .lifted:
            return 1
        case .exiting:
            return 0
        }
    }

    private var overlayOpacity: Double {
        switch phase {
        case .initial, .compressed, .settled, .lifted:
            return 1
        case .exiting:
            return 0
        }
    }

    private var glowScale: CGFloat {
        switch phase {
        case .initial:
            return 0.72
        case .compressed:
            return 0.58
        case .settled:
            return 0.88
        case .lifted:
            return 1.35
        case .exiting:
            return 1.55
        }
    }

    private var glowCoreOpacity: Double {
        switch phase {
        case .initial:
            return 0.18
        case .compressed:
            return 0.14
        case .settled:
            return 0.26
        case .lifted:
            return 0.46
        case .exiting:
            return 0.0
        }
    }

    private var glowMidOpacity: Double {
        switch phase {
        case .initial:
            return 0.12
        case .compressed:
            return 0.09
        case .settled:
            return 0.18
        case .lifted:
            return 0.30
        case .exiting:
            return 0.0
        }
    }

    private var glowEndRadius: CGFloat {
        switch phase {
        case .initial, .compressed:
            return 120
        case .settled:
            return 180
        case .lifted:
            return 310
        case .exiting:
            return 360
        }
    }

    private var symbolGlowOpacity: Double {
        switch phase {
        case .initial:
            return 0.34
        case .compressed:
            return 0.24
        case .settled:
            return 0.58
        case .lifted:
            return 0.88
        case .exiting:
            return 0.0
        }
    }

    private var symbolGlowRadius: CGFloat {
        switch phase {
        case .initial:
            return 18
        case .compressed:
            return 10
        case .settled:
            return 28
        case .lifted:
            return 64
        case .exiting:
            return 72
        }
    }

    private func verticalOffset(in size: CGSize) -> CGFloat {
        switch phase {
        case .initial, .compressed, .settled:
            return 0
        case .lifted:
            return -size.height * 0.31
        case .exiting:
            return -size.height * 0.38
        }
    }
}



#Preview {
    RootView()
        .environment(AuthManager.shared)
        .environment(ThemeManager.shared)
}
