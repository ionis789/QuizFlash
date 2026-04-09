//
//  CanvasModalView.swift
//  QuizFlash
//
//  Full-screen PencilKit drawing canvas presented as a modal sheet.
//  The user can sketch freely and tap Done to save the drawing as PNG data.
//

import SwiftUI
import PencilKit

// MARK: - Canvas Modal View

/// A full-screen drawing canvas that wraps `PKCanvasView` via `CanvasViewRepresentable`.
///
/// - Presents a toolbar with Cancel, Done, and Clear actions.
/// - On "Done", renders the bounded drawing region to a PNG and passes the data
///   back via `onSave`.
/// - Adapts the canvas background colour to the active colour scheme.
struct CanvasModalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// Called with the PNG data of the finalised sketch when the user taps "Done".
    var onSave: (Data) -> Void

    @State private var canvasView = PKCanvasView()
    @State private var toolPicker = PKToolPicker()
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Canvas background — adapts to the active colour scheme.
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

    // MARK: - Private

    private func saveSketch() {
        let bounds = canvasView.drawing.bounds

        guard !bounds.isEmpty else {
            dismiss()
            return
        }

        // Add padding around the drawing content.
        let paddedBounds = bounds.insetBy(dx: -20, dy: -20)

        let image = canvasView.drawing.image(
            from: paddedBounds,
            scale: canvasView.window?.screen.scale ?? canvasView.contentScaleFactor
        )

        if let pngData = image.pngData() {
            onSave(pngData)
        }

        dismiss()
    }
}

// MARK: - Canvas View Representable

/// A `UIViewRepresentable` wrapper around `PKCanvasView` with tool picker support.
///
/// Distinct from the `CanvasView` wrapper in that it accepts a `backgroundColor`
/// parameter for the opaque sketch canvas (white in light mode, black in dark mode).
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

        // Load initial drawing data if provided.
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
