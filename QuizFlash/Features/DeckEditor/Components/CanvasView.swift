import SwiftUI
import PencilKit

// MARK: - Canvas View (PencilKit Bridge)
struct CanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    var toolPicker: PKToolPicker
    var isReadOnly: Bool = false
    var initialData: Data?

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false

        if isReadOnly {
            canvasView.isUserInteractionEnabled = false
        } else {
            toolPicker.setVisible(true, forFirstResponder: canvasView)
            toolPicker.addObserver(canvasView)
            canvasView.becomeFirstResponder()
        }

        if let data = initialData, let drawing = try? PKDrawing(data: data) {
            canvasView.drawing = drawing
        }
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}
