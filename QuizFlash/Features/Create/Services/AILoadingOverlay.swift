//
//  AILoadingOverlay.swift
//  QuizFlash
//

import SwiftUI

// MARK: - AI Loading Overlay
struct AILoadingOverlay: View {
    let state: AIGenerationState
    let onDismiss: () -> Void
    
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)
            
            VStack(spacing: 24) {
                // Animated Icon
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 80, height: 80)
                        .scaleEffect(isPulsing ? 1.1 : 0.95)
                        .shadow(color: .purple.opacity(0.6), radius: isPulsing ? 20 : 10)
                    
                    Image(systemName: iconForState)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, options: .repeating, isActive: true)
                }
                
                // Text & Progress
                VStack(spacing: 12) {
                    Text(titleForState)
                        .font(.title2.weight(.bold))
                    
                    if case .generatingCards(let progress, let foundCount) = state {
                        // Afișăm progresul și cardurile găsite
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(.purple)
                            .frame(height: 8)
                            .clipShape(Capsule())
                            .padding(.horizontal, 20)
                            .animation(.spring(), value: progress)
                        
                        Text("Carduri generate: **\(foundCount)**")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if case .error(let msg) = state {
                        Text(msg)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else {
                        Text("Acest proces poate dura câteva momente.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Error Dismiss Button
                if case .error = state {
                    Button("Închide", action: onDismiss)
                        .font(.headline)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(Color.secondary.opacity(0.2), in: Capsule())
                        .padding(.top, 10)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color(uiColor: .systemBackground))
                    .shadow(color: .black.opacity(0.15), radius: 30, y: 15)
            )
            .padding(.horizontal, 40)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
    
    private var iconForState: String {
        switch state {
        case .extractingText: return "doc.viewfinder"
        case .generatingCards: return "sparkles"
        case .error: return "exclamationmark.triangle.fill"
        case .idle: return ""
        }
    }
    
    private var titleForState: String {
        switch state {
        case .extractingText: return "Se extrage textul..."
        case .generatingCards: return "AI-ul citește..."
        case .error: return "Oops!"
        case .idle: return ""
        }
    }
}
