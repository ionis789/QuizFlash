import SwiftUI
import PencilKit

// MARK: - Canvas View (PencilKit Bridge)

/// A UIViewRepresentable wrapper around `PKCanvasView`.
///
/// - In editable mode (`isReadOnly = false`), shows the tool picker and
///   makes the canvas first responder so the Apple Pencil works immediately.
/// - In read-only mode, disables user interaction so the sketch is displayed
///   as a static image inside the card viewer.
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
