import SwiftUI

// MARK: - Collapsed Pill Constants

enum HeroAnimation {
    /// Scroll pixels after which the pill becomes visible
    static let scrollThreshold: CGFloat = 500
    /// Pill scale when just appearing (grows to 1.0)
    static let pillInitialScale: CGFloat = 0.82
}

// MARK: - DeckCollapsedPill
//
// Fixed overlay. Shows ONLY the collapsed pill once the user has scrolled
// past HeroAnimation.scrollThreshold pixels. The progress is now beautifully
// integrated directly into the capsule's border, matching the navigation bar style.

struct DeckHeroView: View {

    let deck: DeckModel
    let stats: DeckStats

    @Environment(DeckScrollState.self) private var scrollState

    private var pillVisible: Bool { scrollState.pillVisible }

    var body: some View {
        collapsedPill
    }

    private var collapsedPill: some View {
        Text(deck.title)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(height: 50)
            .background {
                AnimatedPillBackground(mastery: stats.deckMastery)
            }
            .opacity(pillVisible ? 1 : 0)
            .scaleEffect(pillVisible ? 1 : HeroAnimation.pillInitialScale, anchor: .top)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: pillVisible)
    }
}

// MARK: - Animated Pill Background

/// Handles the ultraThinMaterial and the dual-layered stroke (inactive white track + active colored progress).
private struct AnimatedPillBackground: View {
    let mastery: Double
    
    @State private var animatedMastery: Double = 0
    @State private var isGlowing: Bool = false
    
    private var ringColor: Color { masteryColor(mastery) }
    
    var body: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay {
                ZStack {
                    // 1. Base Track (Inactive)
                    // Matches the exact blurred, overlay-blended style of the Back button.
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .blur(radius: 10)
                        .mask(Capsule().stroke(lineWidth: 4))
                        .blendMode(.overlay)
                    
                    // 2. Active Progress Border
                    // Colored portion matching the user's mastery level.
                    Capsule()
                        .fill(ringColor.opacity(isGlowing ? 1.0 : 0.85))
                        .blur(radius: isGlowing ? 12 : 8)
                        .mask {
                            Capsule()
                                .trim(from: 0, to: animatedMastery)
                                .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        }
                        // SwiftUI default path draws from 3 o'clock.
                        // Flipping the Y axis makes it start seamlessly from 9 o'clock (left side).
                        .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                }
            }
            .onAppear {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.15)) {
                    animatedMastery = mastery
                }
            }
            .onChange(of: mastery) { old, new in
                guard abs(new - old) > 0.001 else { return }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { animatedMastery = new }
                
                // Trigger a temporary glow effect on update
                withAnimation(.easeIn(duration: 0.2)) { isGlowing = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeInOut(duration: 0.8)) { isGlowing = false }
                }
            }
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

// MARK: - Mastery Color

func masteryColor(_ mastery: Double) -> Color {
    switch mastery {
    case ..<0.25: return .red
    case 0.25..<0.50: return .orange
    case 0.50..<0.75: return .yellow
    case 0.75..<0.90: return .teal
    default: return .green
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
