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

    private var subtitle: String {
        switch state {
        case .photos(let itemCount):
            return itemCount == 1
                ? "OCR is analyzing 1 image."
                : "OCR is analyzing \(itemCount) images."
        case .pdf:
            return "Pages, previews and text quality are being prepared."
        case .none:
            return "Preparing the selected source."
        }
    }

    var body: some View {
        VStack(spacing: UIConstants.Spacing.large) {
            PreparingSourceAnimation(state: state)

            AIGenerationActivityDots(color: ThemeManager.shared.accentColor.color)
                .scaleEffect(1.15)

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PreparingSourceAnimation: View {
    let state: AISourcePreparationState?
    @State private var isPrimaryAnimated = false
    @State private var isSecondaryAnimated = false

    var body: some View {
        ZStack {
            Circle()
                .fill(ThemeManager.shared.accentColor.color.opacity(0.10))
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
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .frame(width: 88, height: 108)
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .offset(
                    x: isSecondaryAnimated ? -16 : -8,
                    y: isSecondaryAnimated ? -12 : -4
                )
                .rotationEffect(.degrees(isSecondaryAnimated ? -9 : -3))

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(ThemeManager.shared.accentColor.color.opacity(0.24))
                .frame(width: 98, height: 118)
                .overlay {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                }
                .offset(x: isPrimaryAnimated ? 10 : 4, y: isPrimaryAnimated ? 10 : -2)
                .shadow(color: ThemeManager.shared.accentColor.color.opacity(0.18), radius: 18, y: 8)
        }
    }

    private var pdfAnimation: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .frame(width: 94, height: 118)
                .offset(
                    x: isSecondaryAnimated ? -10 : -4,
                    y: isSecondaryAnimated ? -6 : 2
                )

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(ThemeManager.shared.accentColor.color.opacity(0.22))
                .frame(width: 102, height: 126)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.88))
                        .frame(width: 52, height: 4)
                        .offset(y: isPrimaryAnimated ? 52 : 28)
                        .blur(radius: 0.2)
                }
                .overlay {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }
                .offset(y: isPrimaryAnimated ? 8 : -4)
                .shadow(color: ThemeManager.shared.accentColor.color.opacity(0.18), radius: 18, y: 8)
        }
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
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 138, height: 98)

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

                Text("\(item.characterCount) chars")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 138, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

struct SourcePreviewOverlay: View {
    let image: UIImage
    let safeAreaInsets: UIEdgeInsets
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.84)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: UIConstants.Spacing.large) {
                HStack {
                    Spacer()

                    ChromeSoftCircleSymbolButton(
                        systemName: "xmark",
                        accessibilityLabel: "Close source preview",
                        action: onClose,
                        symbolSize: UIConstants.Size.iconStandard
                    )
                }

                Spacer(minLength: 0)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: UIConstants.isPad ? 720 : .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.24), radius: UIConstants.Shadow.heavyRadius, y: 8)

                Spacer(minLength: 0)
            }
            .padding(.top, safeAreaInsets.top + UIConstants.Spacing.standard)
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
            .padding(.bottom, safeAreaInsets.bottom + UIConstants.Spacing.large)
        }
    }
}
