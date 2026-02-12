//
//  DraggableImageView.swift
//  QuizFlash
//
//  Created by Ion Socol on 12.02.2026.
//

import SwiftUI

struct DraggableImageView: View {
    @Binding var item: DraggableItem
    var onDelete: () -> Void
    var onTap: () -> Void // Pentru a aduce în față (Z-Index)
    
    // State intern pentru animații haptice
    @State private var isDragging = false
    @State private var hapticScale: CGFloat = 1.0
    
    var body: some View {
        if let uiImage = UIImage(data: item.data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 200, height: 200) // Dimensiune de bază, ajustabilă prin zoom
                // Aplicăm transformările salvate în model
                .rotationEffect(item.rotation)
                .scaleEffect(item.scale * hapticScale)
                .offset(item.offset)
                // Gesturi Combinate (Simultaneous)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDragging = true
                            let currentTranslation = value.translation
                            item.offset = CGSize(
                                width: item.lastOffset.width + currentTranslation.width,
                                height: item.lastOffset.height + currentTranslation.height
                            )
                        }
                        .onEnded { _ in
                            isDragging = false
                            item.lastOffset = item.offset
                        }
                )
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / item.lastScale
                            item.lastScale = value // Tracking temporar
                            item.scale *= delta
                        }
                        .onEnded { value in
                            item.lastScale = 1.0 // Reset pentru următorul gest
                        }
                        .simultaneously(with: RotationGesture()
                            .onChanged { value in
                                let delta = value - item.lastRotation
                                item.lastRotation = value
                                item.rotation += delta
                            }
                            .onEnded { value in
                                item.lastRotation = .zero
                            }
                        )
                )
                // Tap Gesture pentru Focus și Delete (Double Tap)
                .onTapGesture(count: 1) {
                    onTap() // Aduce în față
                }
                .onTapGesture(count: 2) {
                    // Feedback Haptic la ștergere
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.warning)
                    withAnimation { onDelete() }
                }
                .overlay(
                    // Buton mic de ștergere vizibil doar când tragi sau selectezi
                    ZStack {
                        if isDragging {
                            Image(systemName: "trash.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.red)
                                .offset(y: -120) // Deasupra imaginii
                                .rotationEffect(-item.rotation) // Să rămână drept
                        }
                    }
                )
                .zIndex(item.zIndex)
        }
    }
}
