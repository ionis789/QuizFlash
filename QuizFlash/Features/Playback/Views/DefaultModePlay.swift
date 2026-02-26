//
//  DefaultModePlay.swift
//  QuizFlash
//

import SwiftUI
import SwiftData

struct DefaultModePlay: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext

    @State var viewModel: DefaultModePlayViewModel

    private var accentColor: Color { ThemeManager.shared.accentColor.color }
    private var isCompact: Bool { horizontalSizeClass == .compact }

    private var screenBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(uiColor: .systemBackground), Color(uiColor: .secondarySystemBackground)]
            : [Color(uiColor: .systemGray6), Color(uiColor: .systemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // 🟢 Inițializăm ViewModel-ul DOAR cu Deck-ul
    init(deck: DeckModel) {
        _viewModel = State(
            initialValue: DefaultModePlayViewModel(deck: deck)
        )
    }

    var body: some View {
        GeometryReader { geo in
            let isScreenLandscape = geo.size.width > geo.size.height

            ZStack {
                screenBackground
                    .ignoresSafeArea()

                if !viewModel.isComplete {
                    VStack(spacing: 0) {
                        header
                            .padding(.top, 16)
                            .padding(.horizontal, isCompact ? 20 : 32)
                            .padding(.bottom, isCompact ? 20 : 30)

                        cardArea
                            .padding(.horizontal, isCompact ? 16 : (isScreenLandscape ? geo.size.width * 0.15 : 40))
                            .padding(.bottom, isCompact ? 20 : 40)
                    }
                        .transition(.opacity)
                }

                if viewModel.isComplete {
                    completionOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.isComplete)
            .navigationBarHidden(true)
    }

    // MARK: - Card Area
    // MARK: - Card Area
        private var cardArea: some View {
            ZStack {
                if !viewModel.cards.isEmpty && viewModel.currentIndex < viewModel.cards.count {
                    // Randăm STRICT un singur card - cel curent. Fără pre-load.
                    let index = viewModel.currentIndex
                    let card = viewModel.cards[index]

                    @Bindable var bindableViewModel = viewModel

                    GameplayCard(
                        card: card,
                        onSwipe: { direction in
                            viewModel.handleSwipe(direction, context: modelContext)
                        },
                        isFlipped: $bindableViewModel.isFlipped
                    )
                    // Folosim ID-ul unic pentru a forța SwiftUI să înlocuiască vizualul
                    .id(card.persistentModelID)
                    // Opțional: o tranziție simplă ca să nu apară brusc
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.4, dampingFraction: 0.82), value: viewModel.currentIndex)
        }

    // MARK: - Header
    private var header: some View {
        VStack(spacing: 16) {
            ZStack {
                HStack {
                    Spacer()
                    Text(viewModel.deck.title)
                        .font(.headline.bold())
                    Spacer()
                }
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.headline.bold())
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
            }

            // Progress Bar
            HStack(spacing: 4) {
                ForEach(0..<viewModel.cards.count, id: \.self) { index in
                    Capsule()
                        .fill(index < viewModel.currentIndex ? accentColor : Color.gray.opacity(0.5))
                        .frame(height: 4)
                }
            }
                .animation(.spring(response: 0.3), value: viewModel.currentIndex)

            // Q/A Indicator & Stats
            HStack {
                Text(viewModel.isFlipped ? "ANSWER" : "QUESTION")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .animation(.spring(response: 0.3), value: viewModel.isFlipped)

                Spacer()

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("\(viewModel.correctCount)").font(.subheadline.weight(.semibold))
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text("\(viewModel.wrongCards.count)").font(.subheadline.weight(.semibold))
                    }
                }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }

    // MARK: - Completion Overlay
    private var completionOverlay: some View {
        ZStack {
            // Fundal blurat pentru a focusa atenția
            Color.black.opacity(0.5).ignoresSafeArea()
                .background(.ultraThinMaterial)

            VStack(spacing: 0) {
                // Partea Superioară: Victorie și XP
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.yellow.opacity(0.2))
                            .frame(width: 120, height: 120)
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(
                                .linearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                        )
                            .shadow(color: .orange.opacity(0.5), radius: 10, y: 5)
                    }
                        .padding(.bottom, 8)

                    Text("Session Complete!")
                        .font(isCompact ? .title : .largeTitle)
                        .fontWeight(.black)

                    // Badge-ul de XP
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("+\(viewModel.sessionXP) XP")
                            .fontWeight(.bold)
                    }
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                        Capsule().fill(
                                .linearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)
                        )
                    )
                        .shadow(color: .orange.opacity(0.3), radius: 8, y: 4)
                }
                    .padding(.top, 40)
                    .padding(.bottom, 32)

                // Grid-ul cu Statistici (Acuratețe, Timp, Corect, Greșit)
                let accuracy = viewModel.totalSessionSwipes == 0 ? 0 : Int((Double(viewModel.totalSessionCorrect) / Double(viewModel.totalSessionSwipes)) * 100)
                let timeSpent = Date().timeIntervalSince(viewModel.sessionStartTime)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    SessionStatBox(title: "Accuracy", value: "\(accuracy)%", icon: "target", color: .green)
                    SessionStatBox(title: "Time", value: formatTime(timeSpent), icon: "timer", color: .blue)
                    SessionStatBox(title: "Correct", value: "\(viewModel.correctCount)", icon: "checkmark.circle.fill", color: .green)
                    SessionStatBox(title: "Wrong", value: "\(viewModel.wrongCards.count)", icon: "xmark.circle.fill", color: .red)
                }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)

                // Butoanele de acțiune
                VStack(spacing: 16) {
                    if !viewModel.wrongCards.isEmpty {
                        Button {
                            viewModel.retryWrongCards()
                        } label: {
                            Label("Retry Wrong Cards", systemImage: "arrow.counterclockwise")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                                .foregroundStyle(.orange)
                                .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }

                    Button { dismiss() } label: {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.white)
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 10, y: 5)
                    }
                }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
                .background(
                RoundedRectangle(cornerRadius: 32)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.2), radius: 30, y: 15)
            )
                .padding(isCompact ? 24 : 60)
        }
    }

    // Helper pentru formatarea timpului investit
    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

// MARK: - Componentă nouă pentru UI-ul statisticilor din overlay
private struct SessionStatBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(value)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
            .padding(16)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}


private struct StatItem: View {
    let value: String
    let label: String
    var color: Color = .primary
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
