//
//  FlipCardPreview.swift
//  QuizFlash
//
//  Flip card view with text formatting, alignment, and image scaling support.
//

import SwiftUI

struct FlipCardPreview: View {
    let card: CardModel
    var isPreviewMode: Bool = false
    @Binding var isFlipped: Bool
    
    var body: some View {
        ZStack {
            // Back side (shown when flipped)
            cardFace(
                title: "ANSWER",
                blocks: getBlocks(from: card.backContent, legacyText: card.backText, legacyImages: card.backImages)
            )
            .rotation3DEffect(.degrees(isFlipped ? 0 : 180), axis: (x: 0, y: 1, z: 0))
            .opacity(isFlipped ? 1 : 0)
            
            // Front side
            cardFace(
                title: "QUESTION",
                blocks: getBlocks(from: card.frontContent, legacyText: card.frontText, legacyImages: card.frontImages)
            )
            .rotation3DEffect(.degrees(isFlipped ? -180 : 0), axis: (x: 0, y: 1, z: 0))
            .opacity(isFlipped ? 0 : 1)
        }
        .animation(.easeInOut(duration: 0.4), value: isFlipped)
    }
    
    // Get blocks from new format or legacy
    private func getBlocks(from content: CardSideContent, legacyText: String, legacyImages: [Data]) -> [ContentBlock] {
        let validBlocks = content.blocks.filter { block in
            switch block.type {
            case .text: return !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .image, .sketch: return block.imageData != nil
            }
        }
        
        if !validBlocks.isEmpty { return validBlocks }
        
        // Fallback to legacy
        var legacy: [ContentBlock] = []
        if !legacyText.isEmpty { legacy.append(.text(legacyText)) }
        for img in legacyImages { legacy.append(.image(data: img)) }
        return legacy
    }
    
    @ViewBuilder
    private func cardFace(title: String, blocks: [ContentBlock]) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: isPreviewMode ? 16 : 24, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
                    .padding(.leading, 16)
                
                if isPreviewMode {
                    previewContent(blocks: blocks)
                } else {
                    fullContent(blocks: blocks)
                }
            }
        }
    }
    
    // Preview mode (grid thumbnail)
    @ViewBuilder
    private func previewContent(blocks: [ContentBlock]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let txt = blocks.first(where: { $0.type == .text })?.text {
                Text(txt)
                    .font(.subheadline)
                    .lineLimit(3)
            }
            
            if let imgData = blocks.first(where: { $0.type == .image || $0.type == .sketch })?.imageData,
               let img = UIImage(data: imgData) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            if blocks.isEmpty {
                Text("Empty")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
    
    // Full play mode
    @ViewBuilder
    private func fullContent(blocks: [ContentBlock]) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(blocks) { block in
                    blockRenderer(block)
                }
                
                if blocks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "text.quote")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("No content")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
    
    @ViewBuilder
    private func blockRenderer(_ block: ContentBlock) -> some View {
        let alignment: Alignment = {
            switch block.textAlignment {
            case .leading: return .leading
            case .center: return .center
            case .trailing: return .trailing
            }
        }()
        
        switch block.type {
        case .text:
            if !block.text.isEmpty {
                Text(block.text)
                    .font(block.textStyle.font)
                    .fontWeight(block.isBold ? .bold : .regular)
                    .italic(block.isItalic)
                    .multilineTextAlignment(block.textAlignment.alignment)
                    .frame(maxWidth: .infinity, alignment: alignment)
            }
            
        case .image:
            if let data = block.imageData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: UIScreen.main.bounds.width * block.imageScale * 0.8)
                    .frame(maxHeight: 350)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: .infinity, alignment: alignment)
            }
            
        case .sketch:
            if let data = block.imageData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: UIScreen.main.bounds.width * block.imageScale * 0.8)
                    .frame(maxHeight: 350)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: .infinity, alignment: alignment)
            }
        }
    }
}

#Preview {
    FlipCardPreview(
        card: CardModel(frontText: "Test Question", backText: "Test Answer"),
        isFlipped: .constant(false)
    )
    .frame(height: 400)
    .padding()
}
