import SwiftUI

struct FlipCardPreview: View {
    let card: CardModel
    var isPreviewMode: Bool = false
    @Binding var isFlipped: Bool

    var body: some View {
        ZStack {
            // Front
            CardFaceView(
                title: "QUESTION",
                text: card.frontText,
                layoutData: card.frontLayoutData,
                isPreview: isPreviewMode
            )
            .opacity(isFlipped ? 0 : 1)
            .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))

            // Back
            CardFaceView(
                title: "ANSWER",
                text: card.backText,
                layoutData: card.backLayoutData,
                isPreview: isPreviewMode
            )
            .opacity(isFlipped ? 1 : 0)
            .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
        }
    }
}

private struct CardFaceView: View {
    let title: String
    let text: String
    let layoutData: Data?
    let isPreview: Bool
    
    // Decodăm itemii din JSON
    var items: [CanvasItem] {
        guard let data = layoutData else { return [] }
        return (try? JSONDecoder().decode([CanvasItem].self, from: data)) ?? []
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background Card
            RoundedRectangle(cornerRadius: isPreview ? 20 : 30, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 4)

            // Content Container
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    
                    // 1. Text Layer (Scrollable in Play Mode)
                    if isPreview {
                        // Grid Mode: Simplu
                        if !text.isEmpty {
                            Text(text)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .padding(20)
                                .lineLimit(6)
                        } else if !items.isEmpty {
                            // Arată o mică iconiță dacă sunt doar imagini
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        // Play Mode: Full Text
                        ScrollView {
                            Text(text)
                                .font(.system(size: 24))
                                .foregroundStyle(.primary)
                                .padding(24)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    
                    // 2. Image Layer (Freeform)
                    // Le redăm exact cum au fost salvate (relative la centru)
                    ForEach(items) { item in
                        if let uiImage = UIImage(data: item.imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 200, height: 200) // Baza, apoi scalăm
                                .scaleEffect(item.scale * (isPreview ? 0.3 : 1.0)) // Micșorăm în preview
                                .rotationEffect(Angle(degrees: item.rotation))
                                .offset(item.offset) // Offset-ul original
                                .position(x: geo.size.width / 2, y: geo.size.height / 2) // Centru container
                                .zIndex(item.zIndex)
                        }
                    }
                }
            }
            
            // Header Label
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.top, 20)
                .padding(.leading, 24)
                .opacity(0.7)
                .zIndex(100)
        }
        .frame(height: isPreview ? 220 : nil)
    }
}
