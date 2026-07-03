//
//  QuizFlashOnboardingView.swift
//  QuizFlash
//
//  Created by Ion Socol on 03.07.2026.
//

import SwiftUI
import UIKit

// MARK: - QuizFlash Onboarding View

struct QuizFlashOnboardingView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    let presentation: OnboardingPresentation
    let onComplete: @MainActor @Sendable (OnboardingPresentation) -> Void
    let onClose: @MainActor @Sendable (OnboardingPresentation) -> Void

    @State private var currentIndex = 0
    @State private var screenshotSize: CGSize = .zero

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    private var items: [QuizFlashOnboardingItem] {
        QuizFlashOnboardingItem.defaultItems
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            themeManager.screenBackground
                .ignoresSafeArea()

            screenshotView
                .compositingGroup()
                .scaleEffect(
                    items[currentIndex].zoomScale,
                    anchor: items[currentIndex].zoomAnchor
                )
                .frame(maxWidth: maxScreenshotWidth)
                .padding(.top, topContentPadding)
                .padding(.horizontal, horizontalContentPadding)
                .padding(.bottom, bottomControlsHeight + screenshotBottomSpacing)

            bottomControls

            if presentation.allowsClose {
                closeButton
            }

            backButton
        }
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
    }

    // MARK: - Content

    private var screenshotView: some View {
        let frameMetrics = deviceFrameMetrics
        let shape = RoundedRectangle(cornerRadius: frameMetrics.cornerRadius, style: .continuous)

        return GeometryReader { proxy in
            let size = proxy.size

            Rectangle()
                .fill(.black)
                .onAppear {
                    updateScreenshotSize(containerSize: size)
                }
                .onChange(of: size) { _, newValue in
                    updateScreenshotSize(containerSize: newValue)
                }

            HStack(spacing: UIConstants.Spacing.medium) {
                ForEach(items.indices, id: \.self) { index in
                    let item = items[index]

                    Image(item.imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(shape)
                        .frame(width: size.width, height: size.height)
                }
            }
            .offset(x: -CGFloat(currentIndex) * (size.width + UIConstants.Spacing.medium))
        }
        .clipShape(shape)
        .overlay {
            if screenshotSize != .zero {
                ZStack {
                    shape
                        .stroke(.white.opacity(frameMetrics.highlightOpacity), lineWidth: frameMetrics.highlightLineWidth)

                    shape
                        .stroke(.black, lineWidth: frameMetrics.outerLineWidth)

                    shape
                        .stroke(.black, lineWidth: frameMetrics.innerLineWidth)
                        .padding(frameMetrics.innerPadding)
                }
                .padding(frameMetrics.overlayPadding)
            }
        }
        .frame(
            maxWidth: screenshotSize.width == 0 ? nil : screenshotSize.width,
            maxHeight: screenshotSize.height == 0 ? nil : screenshotSize.height
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomControls: some View {
        VStack(spacing: UIConstants.Spacing.medium) {
            textContent
            indicatorView
            continueButton
        }
        .padding(.top, UIConstants.Spacing.large)
        .padding(.horizontal, UIConstants.Spacing.standard)
        .frame(maxWidth: bottomControlsMaxWidth)
        .frame(height: bottomControlsHeight)
        .padding(.bottom, bottomControlsBottomPadding)
    }

    private var textContent: some View {
        GeometryReader { proxy in
            let size = proxy.size

            HStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { index in
                    let item = items[index]
                    let isActive = currentIndex == index

                    VStack(spacing: UIConstants.Spacing.small) {
                        Text(AppLocalization.string(item.titleKey, locale: locale))
                            .font(.title2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .foregroundStyle(.white)

                        Text(AppLocalization.string(item.subtitleKey, locale: locale))
                            .font(.callout.weight(.medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.80))
                    }
                    .frame(width: size.width)
                    .compositingGroup()
                    .blur(radius: isActive ? 0 : 28)
                    .opacity(isActive ? 1 : 0)
                }
            }
            .offset(x: -CGFloat(currentIndex) * size.width)
        }
    }

    private var indicatorView: some View {
        HStack(spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                let isActive = currentIndex == index

                Capsule()
                    .fill(.white.opacity(isActive ? 1 : 0.38))
                    .frame(width: isActive ? 25 : 6, height: 6)
            }
        }
        .padding(.bottom, UIConstants.Spacing.tiny)
    }

    private var continueButton: some View {
        Button {
            if currentIndex == items.count - 1 {
                onComplete(presentation)
                return
            }

            withAnimation(animation) {
                currentIndex = min(currentIndex + 1, items.count - 1)
            }
        } label: {
            Text(AppLocalization.string(currentIndex == items.count - 1 ? "Get started" : "Continue", locale: locale))
                .fontWeight(.medium)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .tint(themeManager.accentColor.color)
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .padding(.horizontal, UIConstants.Spacing.huge)
    }

    private var backButton: some View {
        Button {
            withAnimation(animation) {
                currentIndex = max(currentIndex - 1, 0)
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.title3)
                .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
        }
        .tint(.white)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .opacity(currentIndex == 0 ? 0 : 1)
        .allowsHitTesting(currentIndex > 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, UIConstants.Spacing.standard)
        .padding(.top, UIConstants.Spacing.standard)
    }

    private var closeButton: some View {
        Button {
            onClose(presentation)
        } label: {
            Image(systemName: "xmark")
                .font(.headline.weight(.bold))
                .frame(width: UIConstants.Size.actionButton, height: UIConstants.Size.actionButton)
        }
        .tint(.white)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.trailing, UIConstants.Spacing.standard)
        .padding(.top, UIConstants.Spacing.standard)
    }

    // MARK: - Metrics

    private var isPadLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || horizontalSizeClass == .regular
    }

    private var maxScreenshotWidth: CGFloat? {
        isPadLayout ? 920 : nil
    }

    private var topContentPadding: CGFloat {
        isPadLayout ? 48 : 35
    }

    private var horizontalContentPadding: CGFloat {
        isPadLayout ? 70 : 30
    }

    private var screenshotBottomSpacing: CGFloat {
        isPadLayout ? 70 : 10
    }

    private var bottomControlsHeight: CGFloat {
        isPadLayout ? 230 : 210
    }

    private var bottomControlsMaxWidth: CGFloat? {
        isPadLayout ? 560 : nil
    }

    private var bottomControlsBottomPadding: CGFloat {
        isPadLayout ? 28 : 0
    }

    private var deviceCornerRadius: CGFloat {
        guard let image = UIImage(named: items[currentIndex].imageName) ?? UIImage(named: items[0].imageName) else {
            return 0
        }

        let ratio = screenshotSize.height / image.size.height
        return QuizFlashOnboardingDeviceFrame.pad.actualCornerRadius * ratio
    }

    private var deviceFrameMetrics: QuizFlashOnboardingDeviceFrameMetrics {
        QuizFlashOnboardingDeviceFrameMetrics(
            cornerRadius: deviceCornerRadius,
            highlightLineWidth: 4,
            outerLineWidth: 5,
            innerLineWidth: 4,
            innerPadding: 5,
            overlayPadding: -6,
            highlightOpacity: 0.85
        )
    }

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.22) : .interpolatingSpring(duration: 0.65, bounce: 0, initialVelocity: 0)
    }

    // MARK: - Private

    private func updateScreenshotSize(containerSize: CGSize) {
        guard let imageSize = UIImage(named: items[0].imageName)?.size else { return }
        let fittedSize = imageSize.aspectFit(in: containerSize)

        guard fittedSize != .zero && fittedSize != screenshotSize else { return }
        screenshotSize = fittedSize
    }
}

// MARK: - Item

private struct QuizFlashOnboardingItem: Identifiable, Hashable {
    let id: Int
    let titleKey: String
    let subtitleKey: String
    let imageName: String
    var zoomScale: CGFloat = 1
    var zoomAnchor: UnitPoint = .center

    static let defaultItems: [QuizFlashOnboardingItem] = [
        .init(
            id: 0,
            titleKey: "Track your progress",
            subtitleKey: "Review activity, goals, and recent decks from a focused dashboard.",
            imageName: "OnboardingDashboard",
            zoomScale: 1.08,
            zoomAnchor: .init(x: 0.5, y: 0.15)
        ),
        .init(
            id: 1,
            titleKey: "Organize your library",
            subtitleKey: "Keep every deck easy to find with a clean layout.",
            imageName: "OnboardingLibrary",
            zoomScale: 1.14,
            zoomAnchor: .init(x: 0.5, y: 1.08)
        ),
        .init(
            id: 2,
            titleKey: "Create faster",
            subtitleKey: "Generate cards with AI or add content manually when you need control.",
            imageName: "OnboardingCreate",
            zoomScale: 1.16,
            zoomAnchor: .init(x: 0.5, y: -0.08)
        ),
        .init(
            id: 3,
            titleKey: "Personalize the app",
            subtitleKey: "Adjust goals, text size, navigation, and visual preferences.",
            imageName: "OnboardingSettings",
            zoomScale: 1.16,
            zoomAnchor: .init(x: 0.5, y: 1.08)
        ),
        .init(
            id: 4,
            titleKey: "Build from sources",
            subtitleKey: "Turn documents into flashcards with adjustable source coverage.",
            imageName: "OnboardingSources",
            zoomScale: 1.12,
            zoomAnchor: .init(x: 0.5, y: -0.04)
        )
    ]
}

// MARK: - Metrics

private enum QuizFlashOnboardingDeviceFrame {
    case pad

    var actualCornerRadius: CGFloat {
        72
    }
}

private struct QuizFlashOnboardingDeviceFrameMetrics {
    let cornerRadius: CGFloat
    let highlightLineWidth: CGFloat
    let outerLineWidth: CGFloat
    let innerLineWidth: CGFloat
    let innerPadding: CGFloat
    let overlayPadding: CGFloat
    let highlightOpacity: CGFloat
}

private extension CGSize {
    func aspectFit(in containerSize: CGSize) -> CGSize {
        guard width > 0, height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }

        let scale = min(containerSize.width / width, containerSize.height / height)
        return CGSize(width: width * scale, height: height * scale)
    }
}

#Preview {
    QuizFlashOnboardingView(
        presentation: .preview(UUID()),
        onComplete: { _ in },
        onClose: { _ in }
    )
    .environment(AppPreferences.shared)
    .environment(ThemeManager.shared)
}
