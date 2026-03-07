//
//  AIGenerationSkeletonView.swift
//  QuizFlash
//

import SwiftUI

// MARK: - Extracting Loading State (Noua Animație pentru OCR)

struct AIExtractingLoadingView: View {
    @State private var isScanning = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 60)
            
            ZStack {
                // Document Icon
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 64, weight: .thin))
                    .foregroundStyle(.secondary.opacity(0.4))
                
                // Scanning Laser Line
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .purple.opacity(0.8), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 70, height: 4)
                    .offset(y: isScanning ? 30 : -30)
                    .shadow(color: .purple, radius: 6, y: 0)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: isScanning
                    )
            }
            
            VStack(spacing: 8) {
                Text("Analyzing Document...")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Extracting text and preparing AI generation")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .onAppear {
            isScanning = true
        }
    }
}


// MARK: - Skeleton List

struct AIGenerationSkeletonList: View {

    let cardCount: Int
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<cardCount, id: \.self) { index in
                AISkeletonCardView(index: index, globalAppeared: appeared)
                    .padding(.horizontal, 16)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.94, anchor: .bottom)
                    .offset(y: appeared ? 0 : 20)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.8)
                        .delay(Double(index) * 0.06),
                        value: appeared
                    )
            }
        }
        .onAppear {
            appeared = true
        }
    }
}

// MARK: - Single Skeleton Card (ULTRA OPTIMIZAT)

struct AISkeletonCardView: View {

    let index: Int
    let globalAppeared: Bool

    @State private var phase = false
    @State private var rotation: Double = 0.0

    private let barWidths: [CGFloat]
    
    private let glowColors: [Color] = [
        Color.indigo, Color.cyan, Color.purple,
        Color.orange, Color.pink, Color.indigo
    ]

    init(index: Int, globalAppeared: Bool) {
        self.index = index
        self.globalAppeared = globalAppeared
        var rng = SeededRNG(seed: UInt64(index &* 31337 &+ 1))
        barWidths = (0..<4).map { _ in CGFloat.random(in: 0.45...0.90, using: &rng) }
    }

    var body: some View {
        ZStack {
            // ── 1. Fundal solid opac ──────────────────────────────────────────
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
            
            // ── 2. Flowing Border Super Optimizat (GPU Accelerated) ───────────
            GeometryReader { geo in
                // Desenăm un gradient uriaș pe care GPU-ul îl rotește ieftin
                let maxDim = max(geo.size.width, geo.size.height) * 1.5
                
                AngularGradient(gradient: Gradient(colors: glowColors), center: .center)
                    .frame(width: maxDim, height: maxDim)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .rotationEffect(.degrees(rotation))
            }
            .mask {
                // Gradientul se va vedea strict unde desenăm această mască
                ZStack {
                    // Masca pentru Glow Exterior
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(lineWidth: 4)
                        .blur(radius: 6)
                        .opacity(0.8)
                    
                    // Masca pentru Linia Fină
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(lineWidth: 1.5)
                }
            }
            .opacity(0.85)

            // ── 3. Conținut skeleton ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: 0) {

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.purple.opacity(phase ? 0.35 : 0.18))
                    .frame(width: 64, height: 20)
                    .animation(
                        .easeInOut(duration: 1.1).repeatForever(autoreverses: true).delay(Double(index) * 0.15),
                        value: phase
                    )
                    .padding(.bottom, 14)

                HStack(alignment: .top, spacing: 10) {
                    Text("Q").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.12)).frame(width: 20)
                    VStack(alignment: .leading, spacing: 7) {
                        SkeletonBar(widthFraction: barWidths[0], phase: phase, delayOffset: 0)
                        SkeletonBar(widthFraction: barWidths[1], phase: phase, delayOffset: 0.2)
                    }
                }

                Divider().background(Color.primary.opacity(0.06)).padding(.vertical, 12)

                HStack(alignment: .top, spacing: 10) {
                    Text("A").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.12)).frame(width: 20)
                    VStack(alignment: .leading, spacing: 7) {
                        SkeletonBar(widthFraction: barWidths[2], phase: phase, delayOffset: 0.1)
                        SkeletonBar(widthFraction: barWidths[3], phase: phase, delayOffset: 0.3)
                    }
                }

                HStack {
                    RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(phase ? 0.08 : 0.15)).frame(width: 60, height: 8)
                    Spacer()
                    RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(phase ? 0.08 : 0.15)).frame(width: 80, height: 8)
                }
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(Double(index) * 0.12), value: phase)
                .padding(.top, 14)
            }
            .padding(16)
        }
        .onAppear {
            phase = true
            
            // Această animație rotește gradientul gigant folosind CoreAnimation
            withAnimation(
                .linear(duration: 3.5)
                .repeatForever(autoreverses: false)
            ) {
                rotation = 360.0
            }
        }
    }
}

// MARK: - Skeleton Bar
private struct SkeletonBar: View {
    let widthFraction: CGFloat
    let phase: Bool
    let delayOffset: Double

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(phase ? 0.10 : 0.22))
                .frame(width: geo.size.width * widthFraction, height: 11)
        }
        .frame(height: 11)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true).delay(delayOffset), value: phase)
    }
}

// MARK: - Materialization Wrapper
struct MaterializingCardWrapper<Content: View>: View {
    let isRevealed: Bool
    @ViewBuilder let content: () -> Content
    @State private var burstActive = false

    var body: some View {
        ZStack {
            content()
                .opacity(isRevealed ? 1 : 0)
                .scaleEffect(isRevealed ? 1 : 0.88)
                .blur(radius: isRevealed ? 0 : 3)
                .animation(.spring(response: 0.45, dampingFraction: 0.75), value: isRevealed)

            if burstActive {
                MaterializationBurst().allowsHitTesting(false)
            }
        }
        .onChange(of: isRevealed) { _, revealed in
            guard revealed else { return }
            burstActive = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { burstActive = false }
        }
    }
}

// MARK: - Burst
private struct MaterializationBurst: View {
    @State private var expanded = false
    private let items: [(angle: Double, symbol: String, color: Color)] = [
        (0, "sparkle", .purple), (60, "star.fill", .indigo), (120, "sparkle", .white),
        (180, "star.fill", .purple), (240, "sparkle", .blue), (300, "star.fill", .indigo)
    ]

    var body: some View {
        ZStack {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                Image(systemName: item.symbol)
                    .font(.system(size: i % 2 == 0 ? 9 : 6))
                    .foregroundStyle(item.color.opacity(expanded ? 0 : 0.9))
                    .offset(x: cos(item.angle * .pi / 180) * (expanded ? 44 : 0),
                            y: sin(item.angle * .pi / 180) * (expanded ? 30 : 0))
                    .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(Double(i) * 0.02), value: expanded)
            }
        }
        .onAppear { expanded = true }
    }
}

// MARK: - Seeded RNG
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17; return state
    }
}
