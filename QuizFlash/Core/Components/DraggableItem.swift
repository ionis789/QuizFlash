//
//  DraggableItem.swift
//  QuizFlash
//
//  Created by Ion Socol on 12.02.2026.
//

import SwiftUI

/// Modelul care reține starea fiecărei imagini de pe ecran (poziție, scară, rotație)
struct DraggableItem: Identifiable, Equatable {
    let id = UUID()
    var data: Data // Imaginea propriu-zisă
    
    // Proprietăți pentru gesturi (inspirat din StackItem)
    var offset: CGSize = .zero
    var lastOffset: CGSize = .zero
    
    var scale: CGFloat = 1.0
    var lastScale: CGFloat = 1.0
    
    var rotation: Angle = .zero
    var lastRotation: Angle = .zero
    
    // Pentru a aduce elementul în față la atingere
    var zIndex: Double = 0
}
