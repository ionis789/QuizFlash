import SwiftUI

// MARK: - Root View

struct RootView: View {

    @Environment(AuthManager.self) var authManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(ThemeManager.self) private var themeManager

    @State private var hasStartedLaunchAnimation = false
    @State private var isLaunchAnimationVisible = true
    @State private var isLaunchPulseActive = false
    @State private var isLaunchFlashActive = false
    @State private var isLaunchExiting = false

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
                    isPulseActive: isLaunchPulseActive,
                    isFlashActive: isLaunchFlashActive,
                    isExiting: isLaunchExiting
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
            : .spring(response: 0.48, dampingFraction: 0.72)
        let flashAnimation: Animation = reduceMotion
            ? .easeOut(duration: 0.18)
            : .easeOut(duration: 0.44)
        let exitAnimation: Animation = reduceMotion
            ? .easeInOut(duration: 0.18)
            : .easeInOut(duration: 0.34)

        withAnimation(pulseAnimation) {
            isLaunchPulseActive = true
        }

        try? await Task.sleep(nanoseconds: reduceMotion ? 240_000_000 : 340_000_000)

        withAnimation(flashAnimation) {
            isLaunchFlashActive = true
        }

        try? await Task.sleep(nanoseconds: reduceMotion ? 300_000_000 : 680_000_000)

        withAnimation(exitAnimation) {
            isLaunchExiting = true
        }

        try? await Task.sleep(nanoseconds: reduceMotion ? 190_000_000 : 360_000_000)

        isLaunchAnimationVisible = false
    }
}

// MARK: - Launch Animation

private struct QuizFlashLaunchAnimationView: View {

    @Environment(ThemeManager.self) private var themeManager

    let isPulseActive: Bool
    let isFlashActive: Bool
    let isExiting: Bool

    var body: some View {
        ZStack {
            themeManager.screenBackground
                .ignoresSafeArea()

            ambientGlow

            ZStack {
                pulseRing(size: 166, opacity: isPulseActive ? 0.0 : 0.5)
                    .scaleEffect(isPulseActive ? 1.34 : 0.72)

                pulseRing(size: 120, opacity: isPulseActive ? 0.42 : 0.18)
                    .scaleEffect(isPulseActive ? 1.04 : 0.82)

                symbolPlate

                flashStreak
                    .mask(
                        Circle()
                            .frame(width: 132, height: 132)
                    )
            }
            .scaleEffect(isExiting ? 0.92 : 1.0)
            .opacity(isExiting ? 0.0 : 1.0)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var ambientGlow: some View {
        RadialGradient(
            colors: [
                themeManager.accentColor.color.opacity(isPulseActive ? 0.32 : 0.10),
                themeManager.highlightWarm.opacity(isFlashActive ? 0.16 : 0.04),
                .clear
            ],
            center: .center,
            startRadius: 6,
            endRadius: isPulseActive ? 310 : 130
        )
        .scaleEffect(isPulseActive ? 1.08 : 0.72)
        .opacity(isExiting ? 0.0 : 1.0)
        .ignoresSafeArea()
    }

    private var symbolPlate: some View {
        ZStack {
            Circle()
                .fill(themeManager.surfacePrimary.opacity(0.34))
                .frame(width: 104, height: 104)
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.34),
                                    themeManager.accentColor.color.opacity(0.42),
                                    themeManager.highlightWarm.opacity(0.30)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }

            Image(systemName: "bolt.fill")
                .font(.system(size: 58, weight: .black, design: .rounded))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            .white,
                            themeManager.accentColor.color,
                            themeManager.highlightWarm
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(
                    color: themeManager.accentColor.color.opacity(isPulseActive ? 0.74 : 0.18),
                    radius: isPulseActive ? 28 : 8
                )
                .shadow(
                    color: themeManager.highlightWarm.opacity(isFlashActive ? 0.52 : 0.0),
                    radius: isFlashActive ? 18 : 0
                )
                .scaleEffect(isPulseActive ? 1.0 : 0.68)
                .rotationEffect(.degrees(isPulseActive ? 0 : -8))
        }
    }

    private var flashStreak: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0.0),
                        .white.opacity(isFlashActive ? 0.96 : 0.0),
                        themeManager.highlightWarm.opacity(isFlashActive ? 0.88 : 0.0),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 34, height: 188)
            .blur(radius: 0.8)
            .rotationEffect(.degrees(24))
            .offset(x: isFlashActive ? 96 : -96)
            .blendMode(.screen)
    }

    private func pulseRing(size: CGFloat, opacity: Double) -> some View {
        Circle()
            .stroke(
                themeManager.accentColor.color.opacity(opacity),
                lineWidth: 1.4
            )
            .frame(width: size, height: size)
            .shadow(
                color: themeManager.accentColor.color.opacity(opacity),
                radius: 16
            )
    }
}



#Preview {
    RootView()
        .environment(AuthManager.shared)
        .environment(ThemeManager.shared)
}
