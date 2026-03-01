import SwiftUI

// MARK: - DeckTopBarView

struct DeckTopBarView: View {
    let deck: DeckModel
    let stats: DeckStats
    let viewModel: DeckViewModel
    let searchQuery: String?

    var onBack: () -> Void
    var onEdit: () -> Void

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }



    var body: some View {
        // 1. Citim progresul DIRECT în body pentru a garanta că SwiftUI observă schimbarea la 120Hz
        let currentProgress = viewModel.collapseProgress
        // Sincronizezi apariția header-ului
        let isHeroCollapsed = searchQuery != nil || currentProgress > CollapsingHeaderConfig.heroFadeThreshold

        // ZStack-ul principal: Aici creăm straturile.
        ZStack(alignment: .top) {

            // ── STRATUL 1 (În spate): Fundalul Material și Capsula ─────────
            if isHeroCollapsed {
                ZStack {
                    // Fundalul de sticlă
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea(edges: .top)

                    // Capsula
                    compactPill
                }
                    .frame(height: 52) // Înălțime fixă pentru a se potrivi cu butoanele
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.primary.opacity(0.06))
                        .frame(height: 0.5)
                }
                // Tranziția se aplică DOAR pe fundal și capsulă
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // ── STRATUL 2 (În față): Butoanele de Back și Edit ────────────
            // Acestea stau permanent aici. Nu sunt afectate de tranziție.
            HStack {
                Button(action: onBack) {
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.15), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .frame(width: 40, height: 40)
                            .rotationEffect(.degrees(-90))

                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                    }
                }

                Spacer() // Împinge butoanele spre margini

                if searchQuery == nil {
                    Button(action: onEdit) {
                        ZStack {
                            Circle()
                                .stroke(.white.opacity(0.15), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .frame(width: 40, height: 40)
                                .rotationEffect(.degrees(-90))
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 40, height: 40)
                        }
                    }
                }
            }
                .padding(.horizontal, 20)
                .frame(height: 52) // Aceeași înălțime ca stratul din spate pentru aliniere
        }
        // Animația controlează doar intrarea și ieșirea Stratului 1
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isHeroCollapsed)
    }

    // MARK: - Compact Pill
    private var compactPill: some View {
        let masteryCol = masteryColor(stats.deckMastery)
        let masteryInt = Int(stats.deckMastery * 100)

        return HStack(spacing: 8) {
            Text(deck.title)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)

            ZStack {
                Circle()
                    .stroke(masteryCol.opacity(0.20), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 20, height: 20)
                    .rotationEffect(.degrees(-90))
                Circle()
                    .trim(from: 0, to: stats.deckMastery)
                    .stroke(masteryCol, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 20, height: 20)
                    .rotationEffect(.degrees(-90))
                Text("\(masteryInt)")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(masteryCol)
            }

            if stats.dueCards > 0 {
                ZStack {
                    Circle()
                        .stroke(accent.opacity(0.20), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(-90))
                    Text("\(stats.dueCards)")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                }

            }
        }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.20), lineWidth: 0.5))
    }
}
