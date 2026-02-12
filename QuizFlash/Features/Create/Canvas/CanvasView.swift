import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    var toolPicker: PKToolPicker
    var isReadOnly: Bool = false
    
    // Datele inițiale pentru încărcare
    var initialData: Data?

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput // Permite desenat cu degetul și creionul
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        
        // Configurare ReadOnly (pentru Preview)
        if isReadOnly {
            canvasView.isUserInteractionEnabled = false
        } else {
            // Activăm ToolPicker-ul doar dacă edităm
            toolPicker.setVisible(true, forFirstResponder: canvasView)
            toolPicker.addObserver(canvasView)
            canvasView.becomeFirstResponder()
        }
        
        // Încărcare date inițiale (dacă există)
        if let data = initialData, let drawing = try? PKDrawing(data: data) {
            canvasView.drawing = drawing
        }
        
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Aici putem actualiza starea dacă e necesar
    }
}
