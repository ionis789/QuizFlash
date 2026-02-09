import SwiftUI

struct FlipCardPreview: View {
    let card: CardModel
    var isPreviewMode: Bool = false
    @Binding var isFlipped: Bool

    var body: some View {
        ZStack {
            CardFace(
                title: "QUESTION",
                text: card.frontText,
                isPreview: isPreviewMode,
                enableScroll: false
            )
            .opacity(isFlipped ? 0 : 1)
            .rotation3DEffect(
                .degrees(isFlipped ? 180 : 0),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.6
            )

            CardFace(
                title: "ANSWER",
                text: card.backText,
                isPreview: isPreviewMode,
                enableScroll: !isPreviewMode
            )
            .opacity(isFlipped ? 1 : 0)
            .rotation3DEffect(
                .degrees(isFlipped ? 0 : -180),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.6
            )
        }
        .compositingGroup()
        .accessibilityAddTraits(.isButton)
        .frame(width: isPreviewMode ? 160 : nil, height: isPreviewMode ? 220 : nil)
    }
}

private struct CardFace: View {
    let title: String
    let text: String
    let isPreview: Bool
    let enableScroll: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Color(uiColor: .separator).opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 5)

            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1)

                if isPreview {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                } else if enableScroll {
                    ScrollView {
                        Text(text)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    Text(text)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(6)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped() 
    }
}
