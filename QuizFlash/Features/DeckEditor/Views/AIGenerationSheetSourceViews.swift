//
//  AIGenerationSheetSourceViews.swift
//  QuizFlash
//
//  Source-preparation and preview support views for the AI generation sheet.
//

import SwiftUI

// MARK: - Source Preparation

struct SourcePreparationCenterStage: View {
    let state: AISourcePreparationState?

    private var title: String {
        switch state {
        case .photos:
            return "Extracting text from images"
        case .pdf:
            return "Reading document"
        case .none:
            return "Preparing source"
        }
    }

    var body: some View {
        VStack(spacing: UIConstants.Spacing.large) {
            PreparingSourceAnimation(state: state)

            ProgressActivityDots(color: ThemeManager.shared.accentColor.color)
                .scaleEffect(1.15)

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PreparingSourceAnimation: View {
    let state: AISourcePreparationState?
    @State private var isPrimaryAnimated = false
    @State private var isSecondaryAnimated = false

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.10))
                .frame(width: 164, height: 164)
                .blur(radius: 14)
                .scaleEffect(isPrimaryAnimated ? 1.06 : 0.92)

            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                .frame(width: 138, height: 138)
                .scaleEffect(isSecondaryAnimated ? 1.02 : 0.96)

            switch state {
            case .pdf:
                pdfAnimation
            default:
                photosAnimation
            }
        }
        .frame(height: 190)
        .task {
            guard !isPrimaryAnimated && !isSecondaryAnimated else { return }

            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                isPrimaryAnimated = true
            }

            withAnimation(.easeInOut(duration: 1.85).repeatForever(autoreverses: true)) {
                isSecondaryAnimated = true
            }
        }
    }

    private var photosAnimation: some View {
        ZStack {
            preparationCard(
                width: 88,
                height: 108,
                cornerRadius: 26,
                fill: Color.white.opacity(0.05),
                beamBlur: 8,
                lineWidth: 1.15,
                duration: 2.25
            ) {
                Image(systemName: "photo")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
                .offset(
                    x: isSecondaryAnimated ? -16 : -8,
                    y: isSecondaryAnimated ? -12 : -4
                )
                .rotationEffect(.degrees(isSecondaryAnimated ? -9 : -3))

            preparationCard(
                width: 98,
                height: 118,
                cornerRadius: 28,
                fill: accent.opacity(0.24),
                beamBlur: 9,
                lineWidth: 1.35,
                duration: 2.15
            ) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }
                .offset(x: isPrimaryAnimated ? 10 : 4, y: isPrimaryAnimated ? 10 : -2)
                .shadow(color: accent.opacity(0.18), radius: 18, y: 8)
        }
    }

    private var pdfAnimation: some View {
        ZStack {
            preparationCard(
                width: 94,
                height: 118,
                cornerRadius: 28,
                fill: Color.white.opacity(0.04),
                beamBlur: 8,
                lineWidth: 1.1,
                duration: 2.35
            )
                .offset(
                    x: isSecondaryAnimated ? -10 : -4,
                    y: isSecondaryAnimated ? -6 : 2
                )

            preparationCard(
                width: 102,
                height: 126,
                cornerRadius: 28,
                fill: accent.opacity(0.22),
                beamBlur: 9,
                lineWidth: 1.35,
                duration: 2.15
            ) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.88))
                        .frame(width: 52, height: 4)
                        .offset(y: isPrimaryAnimated ? 52 : 28)
                        .blur(radius: 0.2)
                }
                .offset(y: isPrimaryAnimated ? 8 : -4)
                .shadow(color: accent.opacity(0.18), radius: 18, y: 8)
        }
    }

    private func preparationCard(
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat,
        fill: Color,
        beamBlur: CGFloat,
        lineWidth: CGFloat,
        duration: TimeInterval
    ) -> some View {
        preparationCard(
            width: width,
            height: height,
            cornerRadius: cornerRadius,
            fill: fill,
            beamBlur: beamBlur,
            lineWidth: lineWidth,
            duration: duration
        ) {
            EmptyView()
        }
    }

    private func preparationCard<Content: View>(
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat,
        fill: Color,
        beamBlur: CGFloat,
        lineWidth: CGFloat,
        duration: TimeInterval,
        @ViewBuilder content: () -> Content
    ) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
            .frame(width: width, height: height)
            .aiGenerationBorderBeam(
                accent: accent,
                cornerRadius: cornerRadius,
                beamBlur: beamBlur,
                lineWidth: lineWidth,
                duration: duration
            )
            .overlay(content: content)
    }
}

// MARK: - Source Preview

struct SourcePreviewCard: View {
    let item: AIGenerationSourcePreviewItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(ThemeManager.shared.roleColor(.widgetSurfaceFill))
                        .frame(width: 138, height: 98)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(ThemeManager.shared.roleColor(.widgetSurfaceBorder).opacity(0.22), lineWidth: 1)
                        }

                    if let thumbnail = item.thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 138, height: 98)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(item.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text(item.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 138, alignment: .leading)
        }
        .duoPressableSurfaceStyle()
    }
}

struct SourcePreviewOverlay: View {
    let image: UIImage?
    let safeAreaInsets: UIEdgeInsets
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            BackgroundBlurView(radius: 18)
                .ignoresSafeArea()

            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: UIConstants.Spacing.large) {
                Spacer(minLength: 0)

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: UIConstants.isPad ? 720 : .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.24), radius: UIConstants.Shadow.heavyRadius, y: 8)
                } else {
                    ProgressActivityDots(color: .white)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, safeAreaInsets.top + UIConstants.Spacing.standard)
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            .padding(.bottom, safeAreaInsets.bottom + UIConstants.Spacing.large)
        }
    }
}
