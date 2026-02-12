//
//  CanvasModalView.swift
//  QuizFlash
//
//  Created by Ion Socol on 12.02.2026.
//

import SwiftUI
import PencilKit

struct CanvasModalView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    var onSave: (Data) -> Void
    
    @State private var canvasView = PKCanvasView()
    @State private var toolPicker = PKToolPicker()
    @State private var textBoxes: [TextBox] = []
    
    struct TextBox: Identifiable {
        let id = UUID()
        var text: String = "Text"
        var location: CGPoint
        var color: Color = .primary
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background adaptiv (Gri închis pe Dark, Alb pe Light)
                Color(uiColor: .systemBackground).ignoresSafeArea()
                
                // 1. Layer Desen
                CanvasViewWrapper(canvasView: $canvasView, toolPicker: toolPicker)
                
                // 2. Layer Text
                ForEach($textBoxes) { $box in
                    TextField("", text: $box.text)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(box.color)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.8))
                                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                        )
                        .fixedSize()
                        .position(box.location)
                        .gesture(
                            DragGesture()
                                .onChanged { val in
                                    box.location = val.location
                                }
                        )
                        .contextMenu {
                            Button("Red") { box.color = .red }
                            Button("Blue") { box.color = .blue }
                            Button("Delete", role: .destructive) {
                                textBoxes.removeAll(where: { $0.id == box.id })
                            }
                        }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.red)
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        let center = CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 3)
                        textBoxes.append(TextBox(location: center))
                    } label: {
                        Label("Add Text", systemImage: "textformat")
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { saveComposite() }
                        .fontWeight(.bold)
                }
            }
            .navigationTitle("Sketch")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    @MainActor
    private func saveComposite() {
        let bounds = canvasView.bounds
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        
        let image = renderer.image { ctx in
            // IMPORTANT: Salvăm pe fundal alb sau adaptiv pentru a se vedea desenul
            // Daca e Dark Mode, desenul e alb. Pe foaie alba nu se va vedea.
            // Soluție: Salvăm mereu pe fundal transparent pentru versatilitate, SAU adaptăm.
            
            // Varianta sigură: Fundal transparent (se vede culoarea cardului)
            // Dar desenul alb pe fundal alb nu se vede.
            // Alegem fundal alb pt output (classic paper style)
            UIColor.white.setFill()
            ctx.fill(bounds)
            
            // Desen (PencilKit se desenează peste)
            canvasView.drawing.image(from: bounds, scale: 1).draw(in: bounds)
            
            // Text
            for box in textBoxes {
                let uiColor = UIColor(box.color)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                    .foregroundColor: uiColor
                ]
                let str = NSAttributedString(string: box.text, attributes: attrs)
                let size = str.size()
                let drawPoint = CGPoint(x: box.location.x - size.width/2, y: box.location.y - size.height/2)
                str.draw(at: drawPoint)
            }
        }
        
        if let data = image.jpegData(compressionQuality: 0.8) {
            onSave(data)
        }
        dismiss()
    }
}

struct CanvasViewWrapper: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    var toolPicker: PKToolPicker

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        canvasView.becomeFirstResponder()
        return canvasView
    }
    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}
