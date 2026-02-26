import SwiftUI

struct DeckRowView: View {
    // Am decomentat ViewModel-ul dedicat
    @State private var viewModel: DeckRowViewModel

    private var accent: Color {
        ThemeManager.shared.accentColor.color
    }

    init(deck: DeckModel) {
        // Inițializăm state-ul intern cu VM-ul specific
        _viewModel = State(initialValue: DeckRowViewModel(deck: deck))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // 1. Rândul superior: Titlu și Chevron
            HStack(alignment: .top) {
                Text(viewModel.deck.title)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(white: 0.6))
            }

            // 2. Rândul inferior: Statistici și Badge
            HStack(alignment: .center, spacing: 16) {

                // Numărul de carduri (legat la viewModel)
                HStack(spacing: 6) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14))
                    Text("\(viewModel.totalCards) cards")
                        .font(.system(size: 14, weight: .medium))
                }
                    .foregroundColor(Color(white: 0.7))

                // Timpul scurs (L-am lăsat static deoarece nu era în codul original,
                // dar îl poți schimba în ceva de genul viewModel.lastSyncedString dacă ai proprietatea)
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 14))
                    Text("12 min ago")
                        .font(.system(size: 14, weight: .medium))
                }
                    .foregroundColor(Color(white: 0.7))

                Spacer()

                // Badge-ul mov (Apare doar dacă sunt carduri noi)
                if viewModel.newCardsCount > 0 {
                    ZStack {
                        Circle()
                            .fill(
                            Color(accent).opacity(0.35)
                        )
                            .frame(width: 20, height: 20)

                        Text("\(viewModel.newCardsCount)")
                            .font(.caption2.bold())
                            .foregroundColor(.primary)
                    }
                }
            }
        }
            .padding(16)
            .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                Color.libraryDeckRow
                    .shadow(.inner(color: Color.white.opacity(0.15), radius: 1, x: 0, y: 0))
            )
        }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

    }
}
