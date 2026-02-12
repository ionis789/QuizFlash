//
//  CanvasItemView.swift
//  QuizFlash
//
//  Created by Ion Socol on 12.02.2026.
//

import SwiftUI

struct CanvasItemView: View {
    @Binding var item: CanvasItem
    var isSelected: Bool
    var onSelect: () -> Void
    var onDelete: () -> Void
    
    // State intern pentru gesturi
    @State private var currentScale: CGFloat = 1.0
    @State private var currentRotation: Angle = .zero
    @State private var currentOffset: CGSize = .zero
    
    var body: some View {
        if let uiImage = UIImage(data: item.imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 200, height: 200) // Dimensiune de bază
                // Aplicăm transformările
                .scaleEffect(item.scale * currentScale)
                .rotationEffect(Angle(degrees: item.rotation) + currentRotation)
                .offset(x: item.offset.width + currentOffset.width,
                        y: item.offset.height + currentOffset.height)
                // Border de selecție
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                        .scaleEffect(item.scale * currentScale)
                        .rotationEffect(Angle(degrees: item.rotation) + currentRotation)
                        .offset(x: item.offset.width + currentOffset.width,
                                y: item.offset.height + currentOffset.height)
                )
                // Gesturi Combinate (Simultaneous)
                .gesture(
                    LongPressGesture(minimumDuration: 0.01)
                        .onEnded { _ in onSelect() }
                        .simultaneously(with: DragGesture()
                            .onChanged { value in
                                onSelect()
                                currentOffset = value.translation
                            }
                            .onEnded { value in
                                item.offset.width += value.translation.width
                                item.offset.height += value.translation.height
                                currentOffset = .zero
                            }
                        )
                )
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            currentScale = value
                        }
                        .onEnded { value in
                            item.scale *= value
                            currentScale = 1.0
                        }
                        .simultaneously(with: RotationGesture()
                            .onChanged { value in
                                currentRotation = value
                            }
                            .onEnded { value in
                                item.rotation += value.degrees
                                currentRotation = .zero
                            }
                        )
                )
                .zIndex(item.zIndex) // Ordinea suprapunerii
                // Buton Ștergere (apare doar când e selectat)
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Button {
                            withAnimation { onDelete() }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundStyle(.red)
                                .background(Circle().fill(.white))
                        }
                        .offset(x: 10, y: -10) // Ușor în afara imaginii
                        // Aplicăm aceleași transformări ca să stea lipit de colț
                        .scaleEffect(item.scale * currentScale)
                        .rotationEffect(Angle(degrees: item.rotation) + currentRotation)
                        .offset(x: item.offset.width + currentOffset.width,
                                y: item.offset.height + currentOffset.height)
                    }
                }
        }
    }
}
