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
    @State private var dotCount = 1
    private let loadingPhrases = [
        "Digital neurons warming up...",
        "Turning chaos into knowledge...",
        "Algorithms at work, sit back and relax.",
        "Processing document wisdom...",
        "Teaching circuits new tricks...",
        "Distilling ideas into clarity...",
        "Translating complexity into simplicity...",
        "Spinning up the thinking engine...",
        "Crunching concepts at light speed...",
        "Calibrating intelligence modules...",
        "Brewing fresh insights...",
        "Rewiring thoughts into understanding...",
        "Synthesizing smart summaries...",
        "Charging cognitive processors...",
        "Engineering better understanding...",
        "Mapping ideas into memory...",
        "Assembling knowledge blocks...",
        "Activating deep learning mode...",
        "Compiling brilliance...",
        "Finalizing mental blueprints..."
    ]
    @State private var currentPhrase = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)

            VStack(spacing: 24) {
                // Animated Icon
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                        colors: iconGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                        .frame(width: 80, height: 80)
                        .scaleEffect(isPulsing ? 1.1 : 0.95)
                        .shadow(color: iconGradient[0].opacity(0.6), radius: isPulsing ? 20 : 10)

                    Image(systemName: iconForState)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: isPulsing)
                }

                // Text & Progress
                VStack(spacing: 10) {
                    Text(titleForState)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)

                    if case .error(let msg) = state {
                        Text(msg)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else if case .generatingCards = state {
                        Text(loadingPhrases[currentPhrase])
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .id(currentPhrase)
                    } else {
                        Text(subtitleForState)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Error Dismiss Button
                if case .error = state {
                    Button("Close", action: onDismiss)
                        .font(.headline)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(Color.secondary.opacity(0.2), in: Capsule())
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
            // Change phrase every 2 seconds
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.4)) {
                    currentPhrase = (currentPhrase + 1) % loadingPhrases.count
                }
            }
        }
    }

    private var iconGradient: [Color] {
        switch state {
        case .error: return [.red, .orange]
        case .analyzingDocument: return [.orange, .yellow]
        case .extractingText: return [.blue, .cyan]
        case .generatingCards: return [.purple, .blue]
        case .idle: return [.gray, .gray]
        }
    }

    private var iconForState: String {
        switch state {
        case .analyzingDocument: return "doc.viewfinder"
        case .extractingText: return "text.viewfinder"
        case .generatingCards: return "sparkles"
        case .error: return "exclamationmark.triangle.fill"
        case .idle: return "sparkles"
        }
    }

    private var titleForState: String {
        switch state {
        case .analyzingDocument: return "Analyzing document..."
        case .extractingText: return "Extracting text..."
        case .generatingCards: return "Generating flashcards..."
        case .error: return "Oops!"
        case .idle: return ""
        }
    }

    private var subtitleForState: String {
        switch state {
        case .analyzingDocument: return "Detecting PDF type..."
        case .extractingText: return "Running on-device OCR..."
        default: return "Please wait..."
        }
    }
}
