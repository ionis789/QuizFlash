import SwiftUI

// MARK: - DeckHeroView (Minimal Fitness Rings)



struct DeckHeroView: View {
    let deck: DeckModel
    let stats: DeckStats
    var onEdit: () -> Void

    private var deckColor: Color { Color(hex: deck.colorHex) ?? .blue }

    // MARK: - Stări pentru Animații
    @State private var animatedMastery: Double = 0
    @State private var isGlowing: Bool = false

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: deck.createdAt)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            
            // ── STÂNGA: Titlu și Detalii ──────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text(deck.title)
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                
                Text("\(formattedDate)  •  \(stats.totalCards) carduri")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 0)
            
            // ── DREAPTA: Ring-ul de Mastery Animat ────────────────────
            ZStack {
                // 1. Fundalul inelului
                Circle()
                    .stroke(deckColor.opacity(0.15), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 68, height: 68)
                
                // 2. Progresul colorat (folosind starea animată)
                Circle()
                    .trim(from: 0, to: animatedMastery)
                    .stroke(masteryColor(stats.deckMastery), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 68, height: 68)
                    .rotationEffect(.degrees(-90))
                    // EFECTUL DE GLOW: Se activează doar când isGlowing e True
                    .shadow(color: isGlowing ? masteryColor(stats.deckMastery).opacity(0.8) : .clear, radius: isGlowing ? 15 : 0)
                
                // 3. Procentajul în centru (se actualizează live odată cu linia)
                Text("\(Int(animatedMastery * 100))%")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
        }
        // ── Efectul de Scroll Liber ───────────────────────────────────
        .visualEffect { content, proxy in
            let minY = proxy.frame(in: .named("deckScroll")).minY
            let scrollDistance = max(-minY, 0)
            
            // Tot blocul se dilată și se blurează în sus
            let p = min(scrollDistance / 150.0, 1.0)
            
            return content
                .scaleEffect(1.0 + (p * 0.15), anchor: .bottomLeading)
                .blur(radius: p * 8)
                .opacity(1.0 - p)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        
        // ── 1. ANIMAȚIA LA DESCHIDEREA DECK-ULUI ──────────────────────
        .onAppear {
            // Un delay scurt (0.15s) ca animația să înceapă după tranziția ecranului
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.15)) {
                animatedMastery = stats.deckMastery
            }
        }
        
        // ── 2. ANIMAȚIA ȘI GLOW-UL LA SCHIMBAREA DATELOR (După Quiz) ──
        .onChange(of: stats.deckMastery) { oldValue, newValue in
            // Verificăm dacă valoarea chiar s-a schimbat
            if abs(newValue - oldValue) > 0.001 {
                
                // Animăm noua umplere a ringului
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    animatedMastery = newValue
                }
                
                // Aprindem Glow-ul imediat
                withAnimation(.easeIn(duration: 0.2)) {
                    isGlowing = true
                }
                
                // Stingem Glow-ul lent, după 1.2 secunde
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeInOut(duration: 0.8)) {
                        isGlowing = false
                    }
                }
            }
        }
    }
}

// MARK: - Mastery Color Helper

func masteryColor(_ mastery: Double) -> Color {
    switch mastery {
    case ..<0.25: return .red
    case 0.25..<0.50: return .orange
    case 0.50..<0.75: return .yellow
    case 0.75..<0.90: return .teal
    default: return .green
    }
}


// MARK: - Fitness Rings (Concentric — Apple style)

private struct FitnessRingsView: View {
    let mastery: Double
    let accuracy: Double
    let todayProgress: Double

    @State private var animateRings = false

    var body: some View {
        ZStack {
            // Outer — Mastery
            ringPair(progress: mastery, color: masteryColor(mastery), padding: 0)
            // Middle — Accuracy
            ringPair(progress: accuracy, color: .cyan, padding: 14)
            // Inner — Today
            ringPair(progress: todayProgress, color: .orange, padding: 28)
        }
            .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.interactiveSpring(response: 1, dampingFraction: 1, blendDuration: 1)) {
                    animateRings = true
                }
            }
        }
    }

    private func ringPair(progress: Double, color: Color, padding: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.12), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .padding(padding)
            Circle()
                .trim(from: 0, to: animateRings ? progress : 0)
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .padding(padding)
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Ring Label

private struct RingLabel: View {
    let icon: String
    let color: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }
}


// MARK: - Deck Icon Badge

struct DeckIconBadge: View {
    let icon: String
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.20)).frame(width: size, height: size)
            Circle().stroke(color.opacity(0.30), lineWidth: 0.5).frame(width: size, height: size)
            Image(systemName: icon.isEmpty ? "sparkles.rectangle.stack.fill" : icon)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Compact Mastery Arc

struct CompactMasteryArc: View {
    let mastery: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.15), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 28, height: 28)
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: 0, to: mastery)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 28, height: 28)
                .rotationEffect(.degrees(-90))
            Text("\(Int(mastery * 100))")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(color)
        }
    }
}
