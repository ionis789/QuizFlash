//
//  FlipCard.swift
//  QuizFlash
//

import SwiftUI

struct FlipCard: View {
    let card: CardModel
    @Binding var isFlipped: Bool
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    
    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var cardCornerRadius: CGFloat { isCompact ? 24 : 32 }

    var body: some View {
        // Acum cardul este doar ZStack-ul curat, fără alte elemente UI în jur
        ZStack {
            cardFace(zone: card.backZone)
                .rotation3DEffect(.degrees(isFlipped ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 1 : 0)

            cardFace(zone: card.frontZone)
                .rotation3DEffect(.degrees(isFlipped ? -180 : 0), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 0 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func cardFace(zone: ZoneModel) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(cardBackground)
                .shadow(color: shadowColor, radius: isCompact ? 16 : 24, y: 8)

            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: 1)

            VStack(alignment: .leading, spacing: 0) {
                if zone.hasContent {
                    ScrollView(.vertical, showsIndicators: false) {
                        ZonePreviewView(zone: zone)
                            .padding(.horizontal, isCompact ? 20 : 28)
                            .padding(.vertical, isCompact ? 20 : 24)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    emptyContent
                }
            }
        }
    }

    private var emptyContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.quote")
                .font(.system(size: isCompact ? 40 : 56))
                .foregroundStyle(.tertiary)
            Text("No content")
                .font(isCompact ? .body : .title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cardBackground: some ShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
            : AnyShapeStyle(Color.white)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.12)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)
    }
}
