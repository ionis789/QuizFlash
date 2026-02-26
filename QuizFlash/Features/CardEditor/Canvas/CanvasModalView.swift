//
//  CanvasModalView.swift
//  QuizFlash
//
//  Created by Ion Socol on 12.02.2026.
//

import SwiftUI
import PencilKit
// MARK:  Full-screen drawing canvas modal for creating sketches.
struct CanvasModalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var onSave: (Data) -> Void
    
    @State private var canvasView = PKCanvasView()
    @State private var toolPicker = PKToolPicker()
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Canvas background - adapts to color scheme
                (colorScheme == .dark ? Color(uiColor: .black) : Color.white)
                    .ignoresSafeArea()
                
                // Drawing canvas
                CanvasViewRepresentable(
                    canvasView: $canvasView,
                    toolPicker: toolPicker,
                    backgroundColor: colorScheme == .dark ? .black : .white
                )
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle("Sketch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        saveSketch()
                    }
                    .fontWeight(.semibold)
                }
                
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        canvasView.drawing = PKDrawing()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }
    
    private func saveSketch() {
        // Render canvas to image
        let bounds = canvasView.drawing.bounds
        
        guard !bounds.isEmpty else {
            dismiss()
            return
        }
        
        // Add padding around drawing
        let paddedBounds = bounds.insetBy(dx: -20, dy: -20)
        
        // Render to image with appropriate background
        let image = canvasView.drawing.image(
            from: paddedBounds,
            scale: UIScreen.main.scale
        )
        
        // Convert to PNG data
        if let pngData = image.pngData() {
            onSave(pngData)
        }
        
        dismiss()
    }
}

// MARK: - Canvas View Representable
struct CanvasViewRepresentable: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    var toolPicker: PKToolPicker
    var backgroundColor: UIColor
    var initialData: Data?
    var isReadOnly: Bool = false
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = backgroundColor
        canvasView.isOpaque = true
        
        if isReadOnly {
            canvasView.isUserInteractionEnabled = false
        } else {
            toolPicker.setVisible(true, forFirstResponder: canvasView)
            toolPicker.addObserver(canvasView)
            canvasView.becomeFirstResponder()
        }
        
        // Load initial data if provided
        if let data = initialData, let drawing = try? PKDrawing(data: data) {
            canvasView.drawing = drawing
        }
        
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.backgroundColor = backgroundColor
    }
}

// MARK: - Preview
#Preview {
    CanvasModalView { _ in }
}
