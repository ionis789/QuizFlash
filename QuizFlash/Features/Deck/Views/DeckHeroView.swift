import SwiftUI

// MARK: - Collapsed Pill Constants

enum HeroAnimation {
    /// Scroll pixels after which the pill becomes visible
    static let scrollThreshold : CGFloat = 500
    /// pill scale when just appearing (grows to 1.0)
    static let pillInitialScale: CGFloat = 0.82
    /// small ring diameter inside pill
    static let smallRingSize   : CGFloat = 28
    /// small ring stroke width
    static let smallRingStroke : CGFloat = 3
}

// MARK: - DeckCollapsedPill
//
// Fixed overlay. Shows ONLY the collapsed pill once the user has scrolled
// past HeroAnimation.scrollThreshold pixels. No expanded layer — the title
// is rendered normally as part of the scroll content below.

struct DeckHeroView: View {

    let deck: DeckModel
    let stats: DeckStats

    @Environment(DeckScrollState.self) private var scrollState

    private var deckColor: Color { Color(hex: deck.colorHex) ?? .blue }
    private var pillVisible: Bool { scrollState.pillVisible }

    var body: some View {
        collapsedPill
    }

    private var collapsedPill: some View {
        HStack(spacing: 10) {
            AnimatedRingView(
                mastery: stats.deckMastery,
                deckColor: deckColor,
                size: HeroAnimation.smallRingSize,
                strokeWidth: HeroAnimation.smallRingStroke
            )
            .id("smallRing")
            Text(deck.title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(deckColor.opacity(0.12)))
        )
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .opacity(pillVisible ? 1 : 0)
        .scaleEffect(pillVisible ? 1 : HeroAnimation.pillInitialScale, anchor: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: pillVisible)
    }
}

// MARK: - DeckMasteryRing (public — used in scroll content)

struct DeckMasteryRing: View {
    let mastery: Double
    let deckColor: Color
    var size: CGFloat = 72
    var strokeWidth: CGFloat = 9

    @State private var animatedMastery: Double = 0
    @State private var isGlowing: Bool = false

    private var ringColor: Color { masteryColor(mastery) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(deckColor.opacity(0.2), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: animatedMastery)
                .stroke(ringColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: isGlowing ? ringColor.opacity(0.8) : .clear, radius: isGlowing ? 10 : 0)
            Text("\(Int(animatedMastery * 100))%")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.15)) {
                animatedMastery = mastery
            }
        }
        .onChange(of: mastery) { old, new in
            guard abs(new - old) > 0.001 else { return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { animatedMastery = new }
            withAnimation(.easeIn(duration: 0.2)) { isGlowing = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeInOut(duration: 0.8)) { isGlowing = false }
            }
        }
    }
}



private struct AnimatedRingView: View {
    let mastery: Double
    let deckColor: Color
    let size: CGFloat
    let strokeWidth: CGFloat

    @State private var animatedMastery: Double = 0
    @State private var isGlowing: Bool = false

    private var ringColor: Color { masteryColor(mastery) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(deckColor.opacity(0.2), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: animatedMastery)
                .stroke(ringColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: isGlowing ? ringColor.opacity(0.8) : .clear, radius: isGlowing ? 10 : 0)
            Text("\(Int(animatedMastery * 100))")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundStyle(ringColor)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.15)) {
                animatedMastery = mastery
            }
        }
        .onChange(of: mastery) { old, new in
            guard abs(new - old) > 0.001 else { return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { animatedMastery = new }
            withAnimation(.easeIn(duration: 0.2)) { isGlowing = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeInOut(duration: 0.8)) { isGlowing = false }
            }
        }
    }
}

// MARK: - Mastery Color

func masteryColor(_ mastery: Double) -> Color {
    switch mastery {
    case ..<0.25:     return .red
    case 0.25..<0.50: return .orange
    case 0.50..<0.75: return .yellow
    case 0.75..<0.90: return .teal
    default:          return .green
    }
}

// MARK: - Support Views

struct DeckIconBadge: View {
    let icon: String; let color: Color; let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.20)).frame(width: size, height: size)
            Circle().stroke(color.opacity(0.30), lineWidth: 0.5).frame(width: size, height: size)
            Image(systemName: icon.isEmpty ? "sparkles.rectangle.stack.fill" : icon)
                .font(.system(size: size * 0.38, weight: .bold)).foregroundStyle(.white)
        }
    }
}

struct CompactMasteryArc: View {
    let mastery: Double; let color: Color
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.15), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 28, height: 28).rotationEffect(.degrees(-90))
            Circle().trim(from: 0, to: mastery)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 28, height: 28).rotationEffect(.degrees(-90))
            Text("\(Int(mastery * 100))").font(.system(size: 8, weight: .black)).foregroundStyle(color)
        }
    }
}
