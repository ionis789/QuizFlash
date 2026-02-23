//
//  ZonePreviewSheetView.swift
//  QuizFlash
//

import SwiftUI

// MARK: - Zone Preview Sheet UI-only: full-screen card preview (flip question/answer).
//

struct CardPreviewModeView: View {
    let front: ZoneCardContent
    let back: ZoneCardContent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var isFlipped = false

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var cardCornerRadius: CGFloat { isCompact ? 24 : 32 }
    private var accent: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    backgroundGradient
                        .ignoresSafeArea()

                    VStack(spacing: isCompact ? 16 : 24) {
                        ZStack {
                            cardFace(zone: back.rootZone, title: "Answer", availableHeight: geo.size.height * 0.85)
                                .rotation3DEffect(.degrees(isFlipped ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                                .opacity(isFlipped ? 1 : 0)

                            cardFace(zone: front.rootZone, title: "Question", availableHeight: geo.size.height * 0.85)
                                .rotation3DEffect(.degrees(isFlipped ? -180 : 0), axis: (x: 0, y: 1, z: 0))
                                .opacity(isFlipped ? 0 : 1)
                        }
                            .frame(
                            width: geo.size.width * 0.85,
                            height: geo.size.height * 0.85
                        )
                            .onTapGesture {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                isFlipped.toggle()
                            }
                        }
                    }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
                .navigationTitle("Preview Mode")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func cardFace(zone: ZoneModel, title: String, availableHeight: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: shadowColor, radius: isCompact ? 16 : 24, y: 8)

            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: 1)

            if zone.hasContent {
                GeometryReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            CardFaceView(zone: zone)
                        }
                            .padding(.horizontal, isCompact ? 20 : 28)
                            .padding(.vertical, isCompact ? 20 : 24)
                        // AICI SE ÎNTÂMPLĂ MAGIA CENTRĂRII VERTICALE
                        .frame(minHeight: scrollProxy.size.height, alignment: .center)
                    }
                        .scrollBounceBehavior(.basedOnSize)
                }
                    .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            } else {
                emptyContent
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

    private var backgroundGradient: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(uiColor: .secondarySystemBackground), Color(uiColor: .systemBackground), Color(uiColor: .secondarySystemBackground)]
            : [Color(uiColor: .systemGray6), Color(uiColor: .systemBackground)],
            startPoint: .topLeading,
            endPoint: .bottom
        )
    }

    private var cardBackground: some ShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
        : AnyShapeStyle(Color.white)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.5) : Color.black.opacity(0.15)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
    }
}
