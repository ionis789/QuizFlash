import SwiftUI
import PencilKit

struct CardRowView: View {
    let card: DraftCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Rândul 1: Întrebare
            contentRow(
                label: "Q",
                color: .blue,
                text: card.front,
                type: card.frontType,
                hasImages: !card.frontLayout.isEmpty
            )

            Divider().opacity(0.3)

            // Rândul 2: Răspuns
            contentRow(
                label: "A",
                color: .green,
                text: card.back,
                type: card.backType,
                hasImages: !card.backLayout.isEmpty
            )
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }
    
    @ViewBuilder
    private func contentRow(label: String, color: Color, text: String, type: CardContentType, hasImages: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 24, height: 24)
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
            }
            
            if type == .text {
                if text.isEmpty && hasImages {
                    Label("Image", systemImage: "photo")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(text.isEmpty ? "Empty" : text)
                        .font(.subheadline)
                        .foregroundStyle(text.isEmpty ? Color.secondary.opacity(0.5) : Color.primary)
                        .lineLimit(1)
                }
                
                if hasImages {
                    Image(systemName: "paperclip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                // Canvas Preview
                HStack(spacing: 4) {
                    Image(systemName: "scribble.variable")
                    Text("Sketch")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
}
